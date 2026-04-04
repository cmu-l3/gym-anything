#!/bin/bash
echo "=== Exporting riprap sizing results ==="

source /workspace/scripts/task_utils.sh

# Define paths
CSV_PATH="/home/ga/Documents/hec_ras_results/riprap_design.csv"
TXT_PATH="/home/ga/Documents/hec_ras_results/riprap_summary.txt"
HDF_PATH="$MUNCIE_DIR/Muncie.p04.hdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Output Files
CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
fi

TXT_EXISTS="false"
if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
fi

# 2. Check Simulation Execution
SIMULATION_RUN="false"
if [ -f "$HDF_PATH" ]; then
    HDF_MTIME=$(stat -c %Y "$HDF_PATH" 2>/dev/null || echo "0")
    if [ "$HDF_MTIME" -gt "$TASK_START" ]; then
        SIMULATION_RUN="true"
    fi
fi

# 3. Calculate Ground Truth (Robust Verification)
# We use Python inside the container to calculate the TRUE max velocity from the HDF file
# This allows the verifier to check accuracy without needing the heavy HEC-RAS env itself.
GROUND_TRUTH_JSON="/tmp/ground_truth.json"

if [ -f "$HDF_PATH" ]; then
    cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    hdf_path = sys.argv[1]
    output_path = sys.argv[2]
    
    with h5py.File(hdf_path, 'r') as f:
        # Path to unsteady results for cross sections
        base_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        max_vel = 0.0
        max_rs = ""
        
        # Iterate over all river stations
        if base_path in f:
            grp = f[base_path]
            for rs_name in grp.keys():
                # Get velocity dataset (usually 'Velocity Channel' or 'Velocity Total')
                # Trying 'Velocity Channel' first
                ds_path = f"{base_path}/{rs_name}/Velocity Channel"
                if ds_path in f:
                    data = f[ds_path][:]
                    # Max over time
                    local_max = np.max(data)
                    if local_max > max_vel:
                        max_vel = float(local_max)
                        max_rs = rs_name
        
        result = {
            "ground_truth_available": True,
            "true_max_velocity": max_vel,
            "true_river_station": max_rs
        }
        
        with open(output_path, 'w') as out:
            json.dump(result, out)

except Exception as e:
    with open(output_path, 'w') as out:
        json.dump({"ground_truth_available": False, "error": str(e)}, out)
EOF
    
    # Run the ground truth calculator
    python3 /tmp/calc_ground_truth.py "$HDF_PATH" "$GROUND_TRUTH_JSON"
else
    echo '{"ground_truth_available": false, "error": "HDF file not found"}' > "$GROUND_TRUTH_JSON"
fi

# 4. Prepare Agent Output for Export
# Copy CSV content to a temp file that is guaranteed to be readable
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$CSV_PATH" /tmp/agent_csv.csv
else
    touch /tmp/agent_csv.csv
fi

# 5. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os
import csv

result = {
    'task_start': $TASK_START,
    'csv_exists': '$CSV_EXISTS' == 'true',
    'csv_fresh': '$CSV_MODIFIED_DURING_TASK' == 'true',
    'txt_exists': '$TXT_EXISTS' == 'true',
    'simulation_run': '$SIMULATION_RUN' == 'true',
    'agent_data': {},
    'ground_truth': {}
}

# Read Agent CSV
csv_path = '/tmp/agent_csv.csv'
if os.path.exists(csv_path) and os.path.getsize(csv_path) > 0:
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if rows:
                result['agent_data'] = rows[0]
                # Try to parse numbers
                try:
                    result['agent_data']['max_velocity_fps'] = float(rows[0].get('max_velocity_fps', 0))
                    result['agent_data']['required_d50_ft'] = float(rows[0].get('required_d50_ft', 0))
                except:
                    pass
    except Exception as e:
        result['csv_error'] = str(e)

# Read Ground Truth
gt_path = '$GROUND_TRUTH_JSON'
if os.path.exists(gt_path):
    try:
        with open(gt_path, 'r') as f:
            result['ground_truth'] = json.load(f)
    except:
        pass

print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="