#!/bin/bash
echo "=== Exporting generate_flood_warning_json results ==="

source /workspace/scripts/task_utils.sh

OUTPUT_PATH="/home/ga/Documents/hec_ras_results/dashboard_feed.json"
GROUND_TRUTH_JSON="/tmp/ground_truth_data.json"
MUNCIE_HDF="$MUNCIE_DIR/Muncie.p04.hdf"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if output exists and verify timestamp
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Generate Ground Truth Data (using Python inside container)
# We extract the actual values from the HDF5 file to compare against agent output
echo "Generating ground truth data from HDF5..."
cat << 'PYEOF' > /tmp/generate_ground_truth.py
import h5py
import json
import numpy as np

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
output_path = "/tmp/ground_truth_data.json"

try:
    data = {"cross_sections": {}}
    
    with h5py.File(hdf_path, 'r') as f:
        # 1. Get Geometry (River Stations and Inverts)
        # Path varies by HEC-RAS version, trying standard paths
        geom_path = "Geometry/Cross Sections"
        
        # Get River Stations
        # HEC-RAS stores these as byte strings
        stations = f[f"{geom_path}/River Stations"][()]
        stations = [s.decode('utf-8').strip() for s in stations]
        
        # Get Inverts (Minimum Elevation)
        # 'Station Elevation Info' is usually a 2D array: [Start Index, Count, ...]
        # 'Station Elevation Values' is a 2D array: [Station, Elevation]
        # This is complex to parse generically. 
        # SIMPLER APPROACH FOR VERIFICATION:
        # Use results WSE - Depth if available, or just rely on WSE and Flow correctness.
        # But wait, we need Invert to check the agent's Depth calculation.
        # Let's extract WSE and Flow first, those are easiest.
        
        # Results Paths
        # Unsteady results are usually under /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/
        # Or Summary Output
        
        # Let's try to get Max WSE and Max Flow from Summary if available, or compute max from time series
        
        results_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series"
        cross_section_path = f"{results_path}/Cross Sections"
        
        # Flow and WSE datasets are usually 2D: [Time, CrossSection]
        # We need to map column index to river station.
        # Usually 'Cross Section River Stations' dataset exists in results too.
        
        res_stations_ds = f"{results_path}/Cross Section River Stations"
        res_stations = [s.decode('utf-8').strip() for s in f[res_stations_ds][()]]
        
        flow_ds = f"{results_path}/Flow"
        wse_ds = f"{results_path}/Water Surface"
        
        flow_data = f[flow_ds][()] # Shape: (Time, XS)
        wse_data = f[wse_ds][()]   # Shape: (Time, XS)
        
        # Calculate Max over time axis (axis 0)
        max_flow = np.max(flow_data, axis=0)
        max_wse = np.max(wse_data, axis=0)
        
        # Now we need Invert to verify Depth. 
        # Invert = WSE - Depth (if Depth dataset exists)
        # Often HEC-RAS outputs 'Depth' or 'Hydraulic Depth'. Let's check.
        # If not, we scan geometry.
        
        # Let's try to find minimum elevation from geometry directly for robustness
        # Attributes of Cross Sections often hold node info
        
        for i, station in enumerate(res_stations):
             # Basic ground truth: WSE and Flow
             entry = {
                 "max_wse": float(max_wse[i]),
                 "max_flow": float(max_flow[i]),
                 # We will calculate invert from agent's data if needed or trust WSE verification
             }
             
             # Try to get min elevation from geometry if simple structure
             # (Skipping complex geometry parsing to avoid errors in export script)
             
             data["cross_sections"][station] = entry

    with open(output_path, 'w') as f:
        json.dump(data, f)
        
    print("Ground truth generated successfully")

except Exception as e:
    print(f"Error generating ground truth: {e}")
    # Save partial or error
    with open(output_path, 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

python3 /tmp/generate_ground_truth.py

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move files for copying
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 "$GROUND_TRUTH_JSON" 2>/dev/null || true
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/agent_output.json
    chmod 666 /tmp/agent_output.json
fi

echo "=== Export complete ==="