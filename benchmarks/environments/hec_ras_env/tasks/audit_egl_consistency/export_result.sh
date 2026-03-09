#!/bin/bash
echo "=== Exporting Audit EGL Consistency results ==="

source /workspace/scripts/task_utils.sh

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_FILE="$RESULTS_DIR/egl_profile_audit.csv"
TXT_FILE="$RESULTS_DIR/audit_summary.txt"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Generate Ground Truth (Programmatic check inside container)
# We run a python script to compute the true values from the HDF file
# and save them to a JSON for the verifier to compare against.
echo "Generating ground truth from HDF file..."
cat > /tmp/gen_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys
import os

hdf_path = sys.argv[1]
output_path = sys.argv[2]

try:
    if not os.path.exists(hdf_path):
        print(json.dumps({"error": "HDF file not found"}))
        sys.exit(0)

    with h5py.File(hdf_path, 'r') as f:
        # Paths in HEC-RAS HDF (Standard 6.x structure)
        # Geometry
        geom_path = '/Geometry/Cross Sections'
        try:
            # River Stations (might be byte strings)
            rs_data = f[f'{geom_path}/Attributes'][()]['River Station']
            river_stations = [x.decode('utf-8') if isinstance(x, bytes) else str(x) for x in rs_data]
        except:
             # Fallback for older formats or different structures
            river_stations = []
        
        # Results
        res_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        # 1. Find upstream boundary (max RS)
        # Usually indices match geometry order, but let's assume geometry order is sorted upstream->downstream
        # or we find the index of the max RS.
        # HEC-RAS geometry is usually sorted, index 0 is upstream.
        # Let's verify by finding the max RS value.
        
        try:
            # Convert RS to float for sorting
            rs_floats = [float(x.replace('*','')) for x in river_stations]
            upstream_idx = np.argmax(rs_floats)
            upstream_rs = river_stations[upstream_idx]
        except:
            upstream_idx = 0 # Default to first
            upstream_rs = "Unknown"

        # 2. Find Peak Flow Time Index at Upstream
        flow_ds = f[f'{res_path}/Flow']
        # Extract flow time series for upstream XS (column upstream_idx)
        upstream_flow = flow_ds[:, upstream_idx]
        peak_time_index = int(np.argmax(upstream_flow))
        
        # 3. Extract Snapshot at Peak Time
        wse_snapshot = f[f'{res_path}/Water Surface'] [peak_time_index, :]
        vel_snapshot = f[f'{res_path}/Velocity Total'][peak_time_index, :]
        
        # 4. Compute EGL
        g = 32.174
        egl_snapshot = wse_snapshot + (vel_snapshot**2 / (2*g))
        
        # Structure ground truth
        gt = {
            "peak_time_index": peak_time_index,
            "upstream_rs": upstream_rs,
            "profile": []
        }
        
        for i, rs in enumerate(river_stations):
            gt["profile"].append({
                "rs": rs,
                "wse": float(wse_snapshot[i]),
                "vel": float(vel_snapshot[i]),
                "egl": float(egl_snapshot[i])
            })
            
        with open(output_path, 'w') as out:
            json.dump(gt, out)
            
except Exception as e:
    with open(output_path, 'w') as out:
        json.dump({"error": str(e)}, out)
EOF

# Run the generation script
python3 /tmp/gen_ground_truth.py "$HDF_FILE" /tmp/ground_truth.json

# 3. Check output files
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_FILE")
    CSV_MTIME=$(stat -c %Y "$CSV_FILE")
else
    CSV_EXISTS="false"
    CSV_SIZE="0"
    CSV_MTIME="0"
fi

if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
else
    TXT_EXISTS="false"
fi

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_mtime": $CSV_MTIME,
    "txt_exists": $TXT_EXISTS,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# 5. Move files to /tmp/ for copying
cp "$CSV_FILE" /tmp/user_audit.csv 2>/dev/null || true
cp "$TXT_FILE" /tmp/user_summary.txt 2>/dev/null || true
# Result JSON
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."