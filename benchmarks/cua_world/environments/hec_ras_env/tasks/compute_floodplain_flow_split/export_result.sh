#!/bin/bash
echo "=== Exporting compute_floodplain_flow_split result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/hec_ras_results/flow_distribution.csv"
SUMMARY_PATH="/home/ga/Documents/hec_ras_results/flow_split_summary.txt"
SCRIPT_PATH="/home/ga/Documents/hec_ras_results/flow_split_analysis.py"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check existence and timestamps
CSV_EXISTS="false"
SUMMARY_EXISTS="false"
SCRIPT_EXISTS="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# Run internal verification script to compare agent results with ground truth
# We generate this script on the fly to run inside the container environment
# where h5py and the data files are available.

cat > /tmp/verify_internal.py << 'EOF'
import h5py
import numpy as np
import pandas as pd
import os
import json
import sys

# Paths
hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
agent_csv_path = "/home/ga/Documents/hec_ras_results/flow_distribution.csv"

metrics = {
    "ground_truth_calculated": False,
    "csv_valid_format": False,
    "cross_section_count_match": False,
    "columns_match": False,
    "flow_pct_sum_valid": False,
    "error_lob": 100.0,
    "error_channel": 100.0,
    "error_rob": 100.0,
    "channel_dominance_check": False,
    "peak_timestep_detected": -1
}

def calculate_ground_truth(h_path):
    try:
        with h5py.File(h_path, 'r') as f:
            # Navigate to Cross Section Output
            # Path depends on HEC-RAS version and plan name, usually:
            # /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/
            
            base_path = "/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections"
            
            # Determine available datasets
            if base_path not in f:
                # Try finding valid path
                def find_path(name, node):
                    if isinstance(node, h5py.Group) and name in node.name:
                        return node.name
                    return None
                # Simplification: assume standard path or fail
                return None
            
            # Get Flow data
            # Typically "Flow" is total flow. 
            # We look for "Flow - LOB", "Flow - Channel", "Flow - ROB" 
            # OR "Flow Area" * "Velocity" sub-sections
            
            grp = f[base_path]
            
            # Helper to get dataset safely
            def get_ds(name):
                return grp[name][()] if name in grp else None

            # Try explicit flows first
            flow_lob = get_ds("Flow - LOB")
            flow_ch = get_ds("Flow - Channel")
            flow_rob = get_ds("Flow - ROB")
            flow_total = get_ds("Flow")
            
            # If explicit sub-flows not found, try V*A
            if flow_lob is None:
                va_lob = get_ds("Flow Area - LOB")
                vel_lob = get_ds("Velocity - LOB")
                if va_lob is not None and vel_lob is not None:
                    flow_lob = va_lob * vel_lob
            
            if flow_ch is None:
                va_ch = get_ds("Flow Area - Channel")
                vel_ch = get_ds("Velocity - Channel")
                if va_ch is not None and vel_ch is not None:
                    flow_ch = va_ch * vel_ch
                    
            if flow_rob is None:
                va_rob = get_ds("Flow Area - ROB")
                vel_rob = get_ds("Velocity - ROB")
                if va_rob is not None and vel_rob is not None:
                    flow_rob = va_rob * vel_rob

            # If still None, maybe single Velocity * Area parts?
            # Fallback: if we can't calculate ground truth, we can't verify accuracy heavily
            if flow_total is None:
                return None
                
            # If calculated sub-flows are missing, assume 0 (e.g. no LOB)
            if flow_lob is None: flow_lob = np.zeros_like(flow_total)
            if flow_ch is None: flow_ch = flow_total # worst case assumption
            if flow_rob is None: flow_rob = np.zeros_like(flow_total)
            
            # Find peak timestep based on max total flow at upstream (first XS) or aggregate
            # Let's use max total flow sum across all XS
            total_flow_sum = np.sum(flow_total, axis=1) # Sum across XS
            peak_idx = np.argmax(total_flow_sum)
            metrics["peak_timestep_detected"] = int(peak_idx)
            
            # Extract values at peak
            lob_peak = flow_lob[peak_idx, :]
            ch_peak = flow_ch[peak_idx, :]
            rob_peak = flow_rob[peak_idx, :]
            total_peak = flow_total[peak_idx, :]
            
            # Calculate percentages
            # Handle div by zero
            with np.errstate(divide='ignore', invalid='ignore'):
                lob_pct = np.where(total_peak > 0.001, (lob_peak / total_peak) * 100, 0)
                ch_pct = np.where(total_peak > 0.001, (ch_peak / total_peak) * 100, 0)
                rob_pct = np.where(total_peak > 0.001, (rob_peak / total_peak) * 100, 0)
            
            return {
                "lob": lob_pct,
                "ch": ch_pct,
                "rob": rob_pct,
                "total": total_peak
            }
            
    except Exception as e:
        print(f"GT calc error: {e}")
        return None

gt = calculate_ground_truth(hdf_path)

if gt is not None:
    metrics["ground_truth_calculated"] = True
    
    # Analyze Agent CSV
    if os.path.exists(agent_csv_path):
        try:
            df = pd.read_csv(agent_csv_path)
            metrics["csv_valid_format"] = True
            
            # Check columns
            req_cols = ["LOB_Flow_Pct", "Channel_Flow_Pct", "ROB_Flow_Pct"]
            if all(c in df.columns for c in req_cols):
                metrics["columns_match"] = True
                
                # Check row count
                if len(df) == len(gt["total"]):
                    metrics["cross_section_count_match"] = True
                    
                    # Compare values
                    # Sort by index or CrossSection name? 
                    # Assuming agent preserved order or we simply compare columns
                    # Simple MAE calculation assuming row alignment
                    
                    mae_lob = np.mean(np.abs(df["LOB_Flow_Pct"].values - gt["lob"]))
                    mae_ch = np.mean(np.abs(df["Channel_Flow_Pct"].values - gt["ch"]))
                    mae_rob = np.mean(np.abs(df["ROB_Flow_Pct"].values - gt["rob"]))
                    
                    metrics["error_lob"] = float(mae_lob)
                    metrics["error_channel"] = float(mae_ch)
                    metrics["error_rob"] = float(mae_rob)
                    
                    # Check sum
                    sums = df["LOB_Flow_Pct"] + df["Channel_Flow_Pct"] + df["ROB_Flow_Pct"]
                    if np.all((sums > 98) & (sums < 102)):
                        metrics["flow_pct_sum_valid"] = True
                        
                    # Check Channel Dominance
                    # Real data: Channel usually carries most flow
                    if np.mean(df["Channel_Flow_Pct"]) > 40:
                        metrics["channel_dominance_check"] = True
                        
        except Exception as e:
            print(f"CSV parse error: {e}")

print(json.dumps(metrics))
EOF

# Execute internal verification
VERIFY_JSON="{}"
if [ -f "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf" ]; then
    VERIFY_JSON=$(python3 /tmp/verify_internal.py 2>/dev/null || echo "{}")
fi

# Clean up
rm -f /tmp/verify_internal.py

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "summary_exists": $SUMMARY_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "verification_metrics": $VERIFY_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="