#!/bin/bash
echo "=== Exporting export_results_to_geojson result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/hec_ras_results/muncie_results.geojson"
HDF_PATH="$MUNCIE_DIR/Muncie.p04.hdf"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# ------------------------------------------------------------------
# GENERATE GROUND TRUTH
# We run a trusted script to extract the data from the HDF directly
# into a JSON format that the verifier can easily compare against.
# ------------------------------------------------------------------
echo "Generating ground truth from HDF..."
cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import json
import numpy as np
import sys

hdf_path = sys.argv[1]
output_path = sys.argv[2]

try:
    data = {}
    with h5py.File(hdf_path, 'r') as f:
        # 1. Geometry: Cross Sections
        # Paths vary by RAS version, try standard ones
        geom_base = '/Geometry/Cross Sections'
        
        # Get River Stations
        if f'{geom_base}/River Stations' in f:
            stations = f[f'{geom_base}/River Stations'][:]
            # Decode bytes if needed
            stations = [s.decode('utf-8') if isinstance(s, bytes) else str(s) for s in stations]
        else:
            data['error'] = 'River Stations not found'
            print(json.dumps(data))
            sys.exit(0)
            
        data['cross_section_count'] = len(stations)
        data['stations'] = stations
        
        # Get Coordinates (Polyline)
        # Just grab the first and last to verify geometry without dumping everything
        coords_path = f'{geom_base}/Polyline/Coordinate'
        parts_path = f'{geom_base}/Polyline/Part Starting Index'
        
        if coords_path in f:
            all_coords = f[coords_path][:]
            parts = f[parts_path][:]
            
            # Get coords for first XS
            idx_start = parts[0,0] # usually 2D array [n, 2] or similar structure in RAS? 
            # Actually Polyline/Coordinate is usually a long list of XY, and Part Starting Index maps XS to it.
            # Let's assume standard structure: one part per XS.
            
            # Helper to get coords for index i
            def get_xs_coords(i):
                start = parts[i, 0]
                count = parts[i, 1]
                return all_coords[start:start+count].tolist()

            if len(parts) > 0:
                data['first_xs_coords'] = get_xs_coords(0)
                data['last_xs_coords'] = get_xs_coords(len(parts)-1)
        
        # 2. Results: Peak WSE and Flow
        # Unsteady results are typically time series. We need max.
        # Path: /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/
        results_base = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        if results_base in f:
            # WSE typically "Water Surface"
            if 'Water Surface' in f[results_base]:
                wse_data = f[f'{results_base}/Water Surface'][:] # Shape: [Time, XS]
                # Compute peaks
                peak_wse = np.max(wse_data, axis=0)
                data['peak_wse_sample_first'] = float(peak_wse[0])
                data['peak_wse_sample_last'] = float(peak_wse[-1])
            
            # Flow typically "Flow"
            if 'Flow' in f[results_base]:
                flow_data = f[f'{results_base}/Flow'][:]
                peak_flow = np.max(flow_data, axis=0)
                data['peak_flow_sample_first'] = float(peak_flow[0])
                data['peak_flow_sample_last'] = float(peak_flow[-1])

    with open(output_path, 'w') as out:
        json.dump(data, out)

except Exception as e:
    error_data = {"error": str(e)}
    with open(output_path, 'w') as out:
        json.dump(error_data, out)
PYEOF

python3 /tmp/generate_ground_truth.py "$HDF_PATH" "/tmp/ground_truth.json"

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files for verifier to pick up
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# If output exists, copy it to tmp for easy access by verifier
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/agent_output.geojson
    chmod 666 /tmp/agent_output.geojson
fi

# Ensure ground truth is accessible
chmod 666 /tmp/ground_truth.json 2>/dev/null || true

rm -f "$TEMP_JSON"
echo "=== Export complete ==="