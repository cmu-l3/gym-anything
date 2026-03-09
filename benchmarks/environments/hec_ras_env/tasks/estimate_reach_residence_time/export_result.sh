#!/bin/bash
echo "=== Exporting estimate_reach_residence_time results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/volume_integration.csv"
REPORT_PATH="$RESULTS_DIR/residence_time_report.txt"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check User Outputs
CSV_EXISTS="false"
REPORT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
fi

# 3. Generate Ground Truth (Hidden Calculation)
# We run a python script inside the container to calculate the true values
# This ensures we use the exact libraries and file version present in the env.

cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    with h5py.File('/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf', 'r') as f:
        # 1. Get Geometry Attributes
        # Reach lengths usually in /Geometry/Cross Sections/Attributes or similar
        # Structure varies by RAS version, assuming standard 6.x HDF
        
        # Get River Stations (strings)
        rs_path = '/Geometry/Cross Sections/Attributes'
        if 'River Station' in f[rs_path]:
            river_stations = [x.decode('utf-8') for x in f[rs_path]['River Station']]
        else:
            # Fallback path
            river_stations = []
            
        # Get Channel Lengths (Downstream reach lengths)
        # Usually 'Reach Lengths' column: LOB, Channel, ROB
        lengths_data = f[rs_path]['Reach Length'][:] # Shape (N, 3) usually
        channel_lengths = lengths_data[:, 1] # Index 1 is usually main channel
        
        # 2. Get Flow Results to find Peak Time
        # /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Flow
        flow_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Flow'
        flow_data = f[flow_path][()] # Shape (Time, XS)
        
        # Assume cross sections are stored Upstream -> Downstream in geometry,
        # but check HDF documentation. Usually index 0 is upstream, index -1 is downstream for Muncie.
        # We need peak at DOWNSTREAM boundary.
        q_out_ts = flow_data[:, -1] 
        peak_idx = np.argmax(q_out_ts)
        peak_q = q_out_ts[peak_idx]
        
        # 3. Get Flow Area at Peak Time
        area_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Flow Area'
        area_data = f[area_path][peak_idx, :]
        
        # 4. Calculate Volume (Average End Area)
        # V = Sum( L_i * (A_i + A_{i+1})/2 )
        # Reach length at index i is typically distance to i+1
        # The last XS usually has length 0 or distance to junction
        
        total_vol = 0.0
        n_xs = len(area_data)
        
        # Simple integration
        for i in range(n_xs - 1):
            avg_area = (area_data[i] + area_data[i+1]) / 2.0
            length = channel_lengths[i]
            total_vol += avg_area * length
            
        # 5. Calculate Residence Time
        # T (sec) = Vol / Q
        # T (hr) = T(sec) / 3600
        res_time_hrs = (total_vol / peak_q) / 3600.0 if peak_q > 0 else 0
        
        result = {
            "ground_truth_volume": float(total_vol),
            "ground_truth_time_hrs": float(res_time_hrs),
            "ground_truth_peak_q": float(peak_q),
            "peak_index": int(peak_idx),
            "success": True
        }
        print(json.dumps(result))

except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))
EOF

GROUND_TRUTH_JSON=$(python3 /tmp/calc_ground_truth.py)

# 4. Parse User CSV content (if exists)
USER_CSV_CONTENT=""
if [ "$CSV_EXISTS" = "true" ]; then
    # Read first 5 lines for verification
    USER_CSV_CONTENT=$(head -n 5 "$CSV_PATH" | base64 -w 0)
fi

# 5. Parse User Report content (if exists)
USER_REPORT_VALS=""
if [ "$REPORT_EXISTS" = "true" ]; then
    # Try to extract numbers from report
    USER_REPORT_VALS=$(grep -oE "[0-9]+\.[0-9]+" "$REPORT_PATH" | tr '\n' ' ')
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "user_csv_head_b64": "$USER_CSV_CONTENT",
    "user_report_values_str": "$USER_REPORT_VALS",
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="