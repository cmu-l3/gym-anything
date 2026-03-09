#!/bin/bash
echo "=== Exporting interpolate_virtual_gauge_results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_DIR="/home/ga/Documents/hec_ras_results"
PY_FILE="$OUTPUT_DIR/virtual_gauge_analysis.py"
INFO_FILE="$OUTPUT_DIR/virtual_gauge_info.txt"
CSV_FILE="$OUTPUT_DIR/virtual_gauge_wse.csv"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"

# --- 1. Generate Ground Truth (Inside Container) ---
# We calculate the correct answer now using the actual HDF file environment
# so the verifier (on host) doesn't need HEC-RAS libraries.

cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys
import os

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
if not os.path.exists(hdf_path):
    hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"

try:
    with h5py.File(hdf_path, 'r') as f:
        # Path to Cross Section data (Standard RAS 6.x path)
        # Note: Paths can vary slightly, checking common locations
        base_path = "Geometry/Cross Sections"
        
        # Get River Stations (Attributes)
        # In HEC-RAS HDF, River Stations are usually stored in 'River Stations' dataset 
        # or as attributes. Let's look for the standard dataset.
        rs_path = f"{base_path}/River Stations"
        if rs_path in f:
            river_stations = f[rs_path][:]
            # Decode bytes if necessary
            river_stations = [rs.decode('utf-8') if isinstance(rs, bytes) else rs for rs in river_stations]
        else:
            # Fallback for some versions
            attrs = f[base_path].attrs
            # If complex structure, simplified approach: assume we can find the WSE arrays directly
            # Usually WSE is at Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/
            pass

        # Robust way: Look at Results WSE to get ordering
        res_base = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections"
        
        # Get list of cross sections from Results group
        # HEC-RAS HDF structure usually maps 1:1 with Geometry
        # We need the River Station names to sort them.
        
        # Let's try reading Geometry attributes directly for mapping
        geom_rs_path = "Geometry/Cross Sections/River Stations"
        rs_data = f[geom_rs_path][:]
        rs_strings = [x.decode('utf-8').strip() for x in rs_data]
        
        # Sort RS (Strings that represent numbers, usually high to low)
        # Create list of (index, float_value, string_value)
        rs_list = []
        for idx, rs_str in enumerate(rs_strings):
            try:
                val = float(rs_str)
                rs_list.append((idx, val, rs_str))
            except:
                pass # skip non-numeric RS if any
        
        # Sort descending (Upstream -> Downstream)
        rs_list.sort(key=lambda x: x[1], reverse=True)
        
        # Target: 2nd and 3rd upstream (indices 1 and 2)
        # Note: 0-indexed list. 1st is index 0. 2nd is index 1. 3rd is index 2.
        
        if len(rs_list) < 3:
            result = {"error": "Not enough cross sections"}
            print(json.dumps(result))
            sys.exit(0)
            
        us_idx_geom = rs_list[1][0] # 2nd upstream
        ds_idx_geom = rs_list[2][0] # 3rd upstream
        
        us_rs_val = rs_list[1][1]
        ds_rs_val = rs_list[2][1]
        
        target_rs = (us_rs_val + ds_rs_val) / 2.0
        
        # Extract WSE
        # Path: Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
        wse_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface"
        wse_data = f[wse_path][:] # Shape: (Time, XS) or (XS, Time)? usually (Time, XS)
        
        # Check shape
        # HEC-RAS HDF usually stores time series as (Time, nCrossSections)
        
        us_wse_ts = wse_data[:, us_idx_geom]
        ds_wse_ts = wse_data[:, ds_idx_geom]
        
        # Interpolate
        target_wse_ts = (us_wse_ts + ds_wse_ts) / 2.0
        
        # Prepare output
        ground_truth = {
            "upstream_rs": us_rs_val,
            "downstream_rs": ds_rs_val,
            "target_rs": target_rs,
            "wse_series": target_wse_ts.tolist()[:50], # First 50 for check
            "wse_mean": float(np.mean(target_wse_ts)),
            "wse_max": float(np.max(target_wse_ts)),
            "full_series_length": len(target_wse_ts)
        }
        
        print(json.dumps(ground_truth))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

# Execute Ground Truth Generator
GROUND_TRUTH_JSON=$(python3 /tmp/generate_ground_truth.py)

# --- 2. Check Agent Outputs ---

# Check files exist
[ -f "$PY_FILE" ] && PY_EXISTS="true" || PY_EXISTS="false"
[ -f "$INFO_FILE" ] && INFO_EXISTS="true" || INFO_EXISTS="false"
[ -f "$CSV_FILE" ] && CSV_EXISTS="true" || CSV_EXISTS="false"

# Check creation times
PY_NEW="false"
if [ "$PY_EXISTS" = "true" ]; then
    F_TIME=$(stat -c %Y "$PY_FILE")
    if [ "$F_TIME" -ge "$TASK_START" ]; then PY_NEW="true"; fi
fi

CSV_NEW="false"
if [ "$CSV_EXISTS" = "true" ]; then
    F_TIME=$(stat -c %Y "$CSV_FILE")
    if [ "$F_TIME" -ge "$TASK_START" ]; then CSV_NEW="true"; fi
fi

# Read Agent Info File
AGENT_INFO_CONTENT=""
if [ "$INFO_EXISTS" = "true" ]; then
    AGENT_INFO_CONTENT=$(cat "$INFO_FILE")
fi

# Read Agent CSV (First few lines)
AGENT_CSV_HEAD=""
if [ "$CSV_EXISTS" = "true" ]; then
    AGENT_CSV_HEAD=$(head -n 20 "$CSV_FILE")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 3. Package Result ---

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "script": { "exists": $PY_EXISTS, "created_during_task": $PY_NEW },
        "info": { "exists": $INFO_EXISTS, "content": $(echo "$AGENT_INFO_CONTENT" | jq -R -s '.') },
        "csv": { "exists": $CSV_EXISTS, "created_during_task": $CSV_NEW, "head": $(echo "$AGENT_CSV_HEAD" | jq -R -s '.') }
    },
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard export path
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"