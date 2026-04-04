#!/bin/bash
echo "=== Exporting compute_courant_stability results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/hec_ras_results/courant_analysis.csv"
REPORT_PATH="/home/ga/Documents/hec_ras_results/courant_report.txt"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will run a Python script INSIDE the container to validate the data.
# This avoids needing h5py/pandas on the verifier host.
cat > /tmp/validate_results.py << 'PYEOF'
import json
import os
import time
import pandas as pd
import numpy as np
import h5py
import sys

def validate():
    result = {
        "csv_exists": False,
        "report_exists": False,
        "csv_valid": False,
        "csv_rows": 0,
        "columns_correct": False,
        "velocity_stats": {},
        "courant_stats": {},
        "ground_truth_match": False,
        "internal_consistency": 0.0, # Percentage of rows where C = V*dt/dx
        "report_content": {},
        "errors": []
    }

    csv_path = "/home/ga/Documents/hec_ras_results/courant_analysis.csv"
    report_path = "/home/ga/Documents/hec_ras_results/courant_report.txt"
    hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
    
    # 1. Check Files Existence
    if os.path.exists(csv_path):
        result["csv_exists"] = True
        result["csv_mtime"] = os.path.getmtime(csv_path)
    
    if os.path.exists(report_path):
        result["report_exists"] = True
        with open(report_path, 'r') as f:
            content = f.read().lower()
            result["report_content"]["raw"] = content
            result["report_content"]["has_max"] = "max" in content
            result["report_content"]["has_stable"] = "stable" in content or "marginal" in content or "unstable" in content

    # 2. Analyze CSV Content
    if result["csv_exists"]:
        try:
            df = pd.read_csv(csv_path)
            result["csv_rows"] = len(df)
            
            # Check columns
            req_cols = ["River_Station", "Velocity_fps", "Delta_X_ft", "Courant_Number"]
            cols = [c.strip() for c in df.columns]
            if all(rc in cols for rc in req_cols):
                result["columns_correct"] = True
                
                # Stats
                result["velocity_stats"] = {
                    "min": float(df["Velocity_fps"].min()),
                    "max": float(df["Velocity_fps"].max()),
                    "mean": float(df["Velocity_fps"].mean())
                }
                result["courant_stats"] = {
                    "min": float(df["Courant_Number"].min()),
                    "max": float(df["Courant_Number"].max())
                }
                
                # 3. Ground Truth Generation (extract from HDF)
                try:
                    with h5py.File(hdf_path, 'r') as f:
                        # Attempt to extract computation interval
                        # Usually in Plan Data or computed from Time window
                        # For Muncie p04, dt is typically 60s or similar.
                        # We'll try to deduce it or calculate internal consistency regardless of specific dt 
                        # by checking if C / (V/dx) is constant.
                        
                        # Internal Consistency Check: C = V * dt / dx  =>  dt = C * dx / V
                        # Calculate implied dt for each row
                        df['implied_dt'] = df['Courant_Number'] * df['Delta_X_ft'] / df['Velocity_fps']
                        # Filter out zeros to avoid div by zero
                        valid_rows = df[df['Velocity_fps'] > 0.001]
                        
                        if len(valid_rows) > 0:
                            implied_dts = valid_rows['implied_dt']
                            # If standard dev of implied_dt is low, calculation is consistent
                            dt_std = implied_dts.std()
                            dt_mean = implied_dts.mean()
                            
                            # If std is small relative to mean (< 5%), it's consistent
                            if dt_mean > 0 and (dt_std / dt_mean) < 0.05:
                                result["internal_consistency"] = 1.0
                                result["deduced_dt"] = float(dt_mean)
                            else:
                                result["internal_consistency"] = 0.0
                                result["dt_std_error"] = float(dt_std)
                        
                        # Ground Truth Comparison (Approximate)
                        # We check if the max Courant is reasonable for this model (Muncie usually has C < 5)
                        if result["courant_stats"]["max"] < 100 and result["courant_stats"]["min"] >= 0:
                            result["csv_valid"] = True
                            
                except Exception as e:
                    result["errors"].append(f"HDF verification failed: {str(e)}")
                    # If HDF fails (maybe locked?), fallback to simple consistency
                    pass

            else:
                result["errors"].append(f"Missing columns. Found: {cols}")

        except Exception as e:
            result["errors"].append(f"CSV parse error: {str(e)}")

    print(json.dumps(result))

if __name__ == "__main__":
    validate()
PYEOF

# Run validation
python3 /tmp/validate_results.py > /tmp/validation_output.json 2>/dev/null || echo '{"error": "Validation script failed"}' > /tmp/validation_output.json

# Merge into final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "validation": $(cat /tmp/validation_output.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy/permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="