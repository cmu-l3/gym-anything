#!/bin/bash
echo "=== Exporting compute_stream_power results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check existence of agent files
SCRIPT_EXISTS="false"
CSV_EXISTS="false"
SUMMARY_EXISTS="false"

if [ -f "$RESULTS_DIR/compute_stream_power.py" ]; then SCRIPT_EXISTS="true"; fi
if [ -f "$RESULTS_DIR/stream_power_profile.csv" ]; then CSV_EXISTS="true"; fi
if [ -f "$RESULTS_DIR/stream_power_summary.txt" ]; then SUMMARY_EXISTS="true"; fi

# 3. Check timestamps (Anti-gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$CSV_EXISTS" = "true" ]; then
    CSV_MTIME=$(stat -c %Y "$RESULTS_DIR/stream_power_profile.csv" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate Ground Truth JSON
# We run a python script NOW (hidden from agent) to parse the HDF file 
# and generate the correct data to compare against.
echo "--- Generating Ground Truth ---"
cat > /tmp/gen_gt.py << 'EOF'
import h5py
import numpy as np
import json
import os
import sys

# Define specific weight of water
GAMMA = 62.4

try:
    project_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
    hdf_file = os.path.join(project_dir, "Muncie.p04.tmp.hdf")
    
    if not os.path.exists(hdf_file):
        # Try fallback name
        hdf_file = os.path.join(project_dir, "Muncie.p04.hdf")
        
    if not os.path.exists(hdf_file):
        print(json.dumps({"error": "HDF file not found"}))
        sys.exit(0)

    with h5py.File(hdf_file, 'r') as f:
        # 1. Get Stations
        # Paths vary slightly by version, try standard locations
        try:
            stations_ds = f['Geometry/Cross Sections/River Stations']
            stations = np.array([float(x.decode('utf-8')) for x in stations_ds[:]])
        except:
            # Fallback for older structures
            print(json.dumps({"error": "Could not find stations"}))
            sys.exit(0)
            
        # 2. Get Flow and WSE
        # Shape is usually (Time, CrossSection)
        try:
            base_output = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections']
            flow_data = base_output['Flow'][:]
            wse_data = base_output['Water Surface'][:]
        except:
            print(json.dumps({"error": "Could not find results arrays"}))
            sys.exit(0)

        # 3. Sort stations (Downstream to Upstream usually means Low Station to High Station, 
        #    but HEC-RAS stores them upstream to downstream in the array often. 
        #    We rely on the Station values themselves.)
        
        # Determine sorting index to order stations from downstream (low) to upstream (high)
        # or match the order expected. The prompt asks for "ordered by river station".
        # River stations are distance from downstream. Low = Downstream.
        
        # Let's organize everything by sorted station value (ascending)
        sort_idx = np.argsort(stations)
        stations_sorted = stations[sort_idx]
        flow_sorted = flow_data[:, sort_idx]
        wse_sorted = wse_data[:, sort_idx]
        
        # 4. Find peak flow time at most downstream station (index 0 in sorted)
        # Most downstream = lowest station value
        downstream_flow_series = flow_sorted[:, 0]
        peak_time_idx = np.argmax(downstream_flow_series)
        peak_flow_value = float(downstream_flow_series[peak_time_idx])
        
        # 5. Extract snapshot at peak time
        flow_snapshot = flow_sorted[peak_time_idx, :]
        wse_snapshot = wse_sorted[peak_time_idx, :]
        
        # 6. Compute Slope
        # S_i = abs(WSE_i+1 - WSE_i) / abs(Stat_i+1 - Stat_i)
        # Sorted array: index 0 is downstream (lowest station), index N is upstream
        slopes = np.zeros_like(flow_snapshot)
        
        for i in range(len(stations_sorted) - 1):
            dist = abs(stations_sorted[i+1] - stations_sorted[i])
            drop = abs(wse_snapshot[i+1] - wse_snapshot[i])
            if dist > 0:
                slopes[i] = drop / dist
            else:
                slopes[i] = 0.0
        
        # Handle last point (upstream boundary) - duplicate previous slope
        if len(slopes) > 1:
            slopes[-1] = slopes[-2]
            
        # 7. Compute Stream Power
        stream_power = GAMMA * flow_snapshot * slopes
        
        # 8. Find Max
        max_sp_idx = np.argmax(stream_power)
        max_sp_val = float(stream_power[max_sp_idx])
        max_sp_station = float(stations_sorted[max_sp_idx])
        
        # Output Ground Truth
        gt = {
            "stations": stations_sorted.tolist(),
            "flow": flow_snapshot.tolist(),
            "wse": wse_snapshot.tolist(),
            "slope": slopes.tolist(),
            "stream_power": stream_power.tolist(),
            "max_sp_val": max_sp_val,
            "max_sp_station": max_sp_station,
            "peak_flow_downstream": peak_flow_value,
            "peak_time_index": int(peak_time_idx)
        }
        print(json.dumps(gt))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

# Run the python script to generate ground truth JSON
python3 /tmp/gen_gt.py > /tmp/ground_truth.json 2>/dev/null || echo "{}" > /tmp/ground_truth.json

# 5. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "summary_exists": $SUMMARY_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "results_dir": "$RESULTS_DIR",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move results to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Expose agent outputs for verifier
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$RESULTS_DIR/stream_power_profile.csv" /tmp/agent_output.csv
    chmod 666 /tmp/agent_output.csv
fi
if [ "$SUMMARY_EXISTS" = "true" ]; then
    cp "$RESULTS_DIR/stream_power_summary.txt" /tmp/agent_summary.txt
    chmod 666 /tmp/agent_summary.txt
fi
# Ground truth already in /tmp/ground_truth.json, ensure readable
chmod 666 /tmp/ground_truth.json 2>/dev/null || true

rm -f "$TEMP_JSON"
echo "=== Export complete ==="