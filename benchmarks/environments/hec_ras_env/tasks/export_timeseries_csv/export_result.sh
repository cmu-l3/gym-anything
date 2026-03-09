#!/bin/bash
echo "=== Exporting export_timeseries_csv results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
FLOW_CSV="$RESULTS_DIR/flow_timeseries.csv"
WSE_CSV="$RESULTS_DIR/wse_timeseries.csv"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python Evaluation Script
# We run this INSIDE the container to access h5py and the files directly
cat > /tmp/evaluate_results.py << 'PYEOF'
import json
import os
import time
import sys
import pandas as pd
import numpy as np
import h5py

results = {
    "flow_exists": False,
    "wse_exists": False,
    "flow_created_during_task": False,
    "wse_created_during_task": False,
    "flow_columns_valid": False,
    "wse_columns_valid": False,
    "flow_data_reasonable": False,
    "wse_data_reasonable": False,
    "time_monotonic": False,
    "row_count_match": False,
    "hdf_match_score": 0.0,
    "errors": []
}

try:
    flow_path = sys.argv[1]
    wse_path = sys.argv[2]
    hdf_path = sys.argv[3]
    task_start = float(sys.argv[4])

    # --- Check Files Existence & Timestamps ---
    if os.path.exists(flow_path):
        results["flow_exists"] = True
        if os.path.getmtime(flow_path) > task_start:
            results["flow_created_during_task"] = True
    
    if os.path.exists(wse_path):
        results["wse_exists"] = True
        if os.path.getmtime(wse_path) > task_start:
            results["wse_created_during_task"] = True

    # --- Load DataFrames ---
    df_flow = None
    df_wse = None

    if results["flow_exists"]:
        try:
            df_flow = pd.read_csv(flow_path)
            # Check headers
            if "Time" in df_flow.columns or "time" in df_flow.columns:
                if len(df_flow.columns) > 5: # At least Time + 5 stations
                    results["flow_columns_valid"] = True
            
            # Check values
            numeric_cols = df_flow.select_dtypes(include=[np.number])
            if not numeric_cols.empty:
                # Flow should be non-negative (mostly) and < 100,000 for Muncie
                if numeric_cols.max().max() < 100000 and numeric_cols.min().min() > -100:
                    results["flow_data_reasonable"] = True
        except Exception as e:
            results["errors"].append(f"Flow CSV read error: {str(e)}")

    if results["wse_exists"]:
        try:
            df_wse = pd.read_csv(wse_path)
             # Check headers
            if "Time" in df_wse.columns or "time" in df_wse.columns:
                if len(df_wse.columns) > 5:
                    results["wse_columns_valid"] = True
            
            # Check values
            numeric_cols_wse = df_wse.select_dtypes(include=[np.number])
            if not numeric_cols_wse.empty:
                # WSE for Muncie is approx 900-1000 ft
                if numeric_cols_wse.max().max() < 2000 and numeric_cols_wse.min().min() > 500:
                    results["wse_data_reasonable"] = True
        except Exception as e:
            results["errors"].append(f"WSE CSV read error: {str(e)}")

    # --- Consistency Checks ---
    if df_flow is not None and df_wse is not None:
        if len(df_flow) == len(df_wse) and len(df_flow) > 10:
            results["row_count_match"] = True
        
        # Check time monotonicity on flow
        time_col = df_flow.iloc[:, 0]
        # Attempt to parse time if string
        try:
            if time_col.dtype == object:
                time_vals = pd.to_datetime(time_col)
            else:
                time_vals = time_col
            
            if time_vals.is_monotonic_increasing:
                results["time_monotonic"] = True
        except:
            pass # Failed to parse time

    # --- HDF5 Ground Truth Comparison (Spot Check) ---
    if results["flow_exists"] and results["wse_exists"] and os.path.exists(hdf_path):
        try:
            with h5py.File(hdf_path, 'r') as f:
                # Typical path for 1D results in HEC-RAS HDF
                # Try finding Cross Sections path
                base_path = "/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections"
                if base_path in f:
                    flow_ds = f[base_path + "/Flow"]
                    wse_ds = f[base_path + "/Water Surface"]
                    
                    # shape is usually (Time, Station)
                    # Need to map CSV columns to Station Indices
                    # Get Station Names
                    # Station names are stored as attributes or a separate dataset
                    # In RAS HDF, attributes on the group often hold names, or "River Stations" dataset in Geometry
                    
                    # For Muncie (simple 1D), let's just check ranges and approximate means to avoid complex mapping logic failure
                    # If the max flow in HDF matches max flow in CSV within 1%, that's a good sign
                    
                    hdf_max_flow = np.max(flow_ds[()])
                    csv_max_flow = df_flow.select_dtypes(include=[np.number]).max().max()
                    
                    hdf_mean_wse = np.mean(wse_ds[()])
                    csv_mean_wse = df_wse.select_dtypes(include=[np.number]).mean().mean()
                    
                    matches = 0
                    if abs(hdf_max_flow - csv_max_flow) / (hdf_max_flow + 1e-6) < 0.05: # 5% tolerance
                        matches += 1
                    
                    if abs(hdf_mean_wse - csv_mean_wse) / (hdf_mean_wse + 1e-6) < 0.05:
                        matches += 1
                        
                    results["hdf_match_score"] = matches / 2.0
                    
        except Exception as e:
            results["errors"].append(f"HDF5 comparison failed: {str(e)}")

except Exception as e:
    results["errors"].append(f"Evaluation script fatal error: {str(e)}")

print(json.dumps(results))
PYEOF

# 4. Run Evaluation
echo "Running evaluation script..."
# Ensure h5py is installed (should be from install_hec_ras.sh)
EVAL_JSON=$(python3 /tmp/evaluate_results.py "$FLOW_CSV" "$WSE_CSV" "$HDF_FILE" "$TASK_START")
echo "$EVAL_JSON" > /tmp/task_result.json

# 5. Output for logging
cat /tmp/task_result.json

echo "=== Export complete ==="