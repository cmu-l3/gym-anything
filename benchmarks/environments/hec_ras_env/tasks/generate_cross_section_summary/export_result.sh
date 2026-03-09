#!/bin/bash
echo "=== Exporting generate_cross_section_summary results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_CSV="/home/ga/Documents/hec_ras_results/cross_section_summary.csv"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
GROUND_TRUTH_JSON="/tmp/ground_truth.json"

# 3. Check timestamps and file existence
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_CSV" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_CSV" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate Ground Truth from the HDF file (using Python inside the container)
# This ensures we verify against the ACTUAL data present in the environment.
cat > /tmp/extract_ground_truth.py << 'PYEOF'
import h5py
import json
import numpy as np
import os
import sys

hdf_path = sys.argv[1]
output_json = sys.argv[2]

data = {
    "valid": False,
    "cross_sections": []
}

try:
    if not os.path.exists(hdf_path):
        raise FileNotFoundError(f"HDF file not found: {hdf_path}")

    with h5py.File(hdf_path, 'r') as f:
        # Paths for 1D Unsteady Muncie model
        # Note: Paths might vary slightly by RAS version, trying standard ones
        
        # 1. Get River Stations (Geometry)
        # Typically in /Geometry/Cross Sections/Attributes or similar
        # For simple 1D, stations are often implicitly ordered or in Attributes
        
        # Try to find the Cross Sections paths
        geom_path = "/Geometry/Cross Sections"
        res_path = "/Results/Unsteady/Output/Output Blocks/Base Output/Summary Output/Cross Sections"
        
        if geom_path not in f or res_path not in f:
             # Fallback for Steady or different struct
             raise ValueError("Could not find standard RAS HDF paths")

        # Read Attributes for Station Names
        # 'River Station' is usually column 'River Station' in Attributes table
        # But h5py reads compound datasets.
        
        # Let's try to get data directly from Summary Output which usually aligns everything
        # Summary Output often contains 'River Station' as a dataset or attribute
        
        # In HEC-RAS HDF, "River Station" is often stored as byte strings in Geometry attributes
        # Let's iterate through the Result cross sections which should match Geometry
        
        # For verification, we extract the raw arrays if possible
        # Check for 'Maximum Water Surface', 'Maximum Flow', 'Maximum Velocity'
        
        # Let's look at /Geometry/Cross Sections/Attributes
        # It usually has a compound type with 'River Station'
        
        stations = []
        min_els = []
        
        # Extract Geometry Info
        if "Attributes" in f[geom_path]:
            attrs = f[geom_path]["Attributes"][:]
            # Assuming 'River Station' is a field. If not, we might need another approach.
            # HEC-RAS 6.x usually has 'River Station' as first field
            try:
                stations = [x[0].decode('utf-8').strip() for x in attrs] # Assuming index 0 is RS
            except:
                # Fallback: try field name
                if 'River Station' in attrs.dtype.names:
                    stations = [x['River Station'].decode('utf-8').strip() for x in attrs]
        
        # Extract Min Ch El
        # Often in 'Minimum Channel Elevation' in Geometry attributes or computed
        # For simplicity in verification, let's grab it from Results if available, or Geometry
        # In /Geometry/Cross Sections/Attributes, there is usually 'Minimum Channel Elevation'
        
        if 'Minimum Channel Elevation' in f[geom_path]['Attributes'].dtype.names:
             min_els = f[geom_path]['Attributes']['Minimum Channel Elevation'][:]
        
        # Extract Results
        # Paths: 
        # .../Maximum Water Surface
        # .../Maximum Flow
        # .../Maximum Velocity - Total
        
        wse_ds = f[res_path]['Maximum Water Surface'][:]
        flow_ds = f[res_path]['Maximum Flow'][:]
        vel_ds = f[res_path]['Maximum Velocity - Total'][:]
        
        # Combine
        # Note: arrays should be same length
        for i in range(len(stations)):
            rs = stations[i]
            min_el = float(min_els[i])
            wse = float(wse_ds[i])
            flow = float(flow_ds[i])
            vel = float(vel_ds[i])
            
            data["cross_sections"].append({
                "River_Station": rs,
                "Min_Ch_El_ft": min_el,
                "Peak_WSE_ft": wse,
                "Peak_Flow_cfs": flow,
                "Peak_Vel_fps": vel,
                "Max_Depth_ft": wse - min_el
            })
            
    data["valid"] = True

except Exception as e:
    data["error"] = str(e)

with open(output_json, 'w') as out:
    json.dump(data, out, indent=2)

PYEOF

# Run extraction script
python3 /tmp/extract_ground_truth.py "$HDF_FILE" "$GROUND_TRUTH_JSON" || echo "Extraction failed"

# 5. Prepare output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "ground_truth_available": $([ -f "$GROUND_TRUTH_JSON" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Copy files to /tmp/task_result.json for framework
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

# Copy CSV and GT for verifier
cp "$OUTPUT_CSV" /tmp/agent_output.csv 2>/dev/null || true
chmod 666 /tmp/agent_output.csv 2>/dev/null || true
chmod 666 "$GROUND_TRUTH_JSON" 2>/dev/null || true

echo "Export complete."