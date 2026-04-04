#!/bin/bash
echo "=== Exporting Geometry Containment Results ==="

source /workspace/scripts/task_utils.sh

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_HDF="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Output Files
CSV_FILE="$RESULTS_DIR/geometry_containment.csv"
JSON_FILE="$RESULTS_DIR/critical_sections.json"
PLOT_FILE="$RESULTS_DIR/containment_profile.png"

CSV_EXISTS="false"
JSON_EXISTS="false"
PLOT_EXISTS="false"

if [ -f "$CSV_FILE" ]; then CSV_EXISTS="true"; fi
if [ -f "$JSON_FILE" ]; then JSON_EXISTS="true"; fi
if [ -f "$PLOT_FILE" ]; then PLOT_EXISTS="true"; fi

# 3. Generate Ground Truth (Hidden from agent)
# We run a Python script to calculate the ACTUAL values from the HDF file
# to compare against what the agent produced.
cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import json
import os
import sys

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
output_path = "/tmp/ground_truth.json"

if not os.path.exists(hdf_path):
    print(json.dumps({"error": "HDF file not found"}))
    sys.exit(0)

try:
    with h5py.File(hdf_path, 'r') as f:
        # Determine paths (handle standard RAS HDF structure)
        # 1. Get River Stations
        # Paths vary by version, try standard ones
        xs_base = None
        if '/Geometry/Cross Sections' in f:
            xs_base = f['/Geometry/Cross Sections']
        
        results_base = None
        if '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections' in f:
            results_base = f['/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections']

        if not xs_base or not results_base:
            print(json.dumps({"error": "HDF structure not recognized"}))
            sys.exit(0)
            
        # Get Attributes (Names/Stations)
        # Station names are often in 'River Stations' or similar
        # Depending on version, might be byte strings
        try:
            stations = xs_base['River Stations'][:]
        except:
            # Fallback for some versions
            stations = xs_base['Attributes'][:] # This might be struct array
            
        # Convert to string list
        station_list = []
        for s in stations:
            if isinstance(s, bytes):
                station_list.append(s.decode('utf-8').strip())
            else:
                station_list.append(str(s).strip())

        # Calculate metrics
        data = []
        
        # Geometry: Station Elevation data usually stored as 'Station Elevation' dataset 
        # But in some RAS versions, it's organized differently. 
        # Simpler approach: Check if we can access the computed WSE max and verify against that.
        # But we need Max Terrain.
        # Let's assume standard 6.x structure: /Geometry/Cross Sections/Station Elevation
        # This is typically a 1D array of combined data or 2D array.
        # Actually, in 6.x, it might be sparse. 
        # Alternative: We trust the agent's extraction logic if we can't easily reproduce it without Rashdf?
        # No, we must try.
        
        # Let's extract Max WSE directly from Results
        wse_data = results_base['Water Surface'][:]
        # Shape is (Time, XS)
        max_wse = np.max(wse_data, axis=0)
        
        # For Terrain Max, we might need to look at specific geometry tables
        # If we can't reliably get Terrain Max from this raw script, 
        # we will focus verification on the WSE values and the logic (Negative freeboard plausibility).
        # However, typically 'Station Elevation' is available.
        # Let's assume we can get it or approximate it.
        # For the purpose of this verifier, we will extract the MAX WSE for the first and last station
        # and use that as a signature.
        
        ground_truth = {
            "stations": station_list,
            "max_wse_values": max_wse.tolist(),
            "count": len(station_list)
        }
        
        # Critical checks
        # We can't easily replicate the complex geometry parsing in a short script without external libs
        # So we will verify the WSE values match the HDF (proving they read the file)
        # And check consistency of the agent's CSV.
        
        print(json.dumps(ground_truth))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

python3 /tmp/generate_ground_truth.py > /tmp/ground_truth_data.json 2>/dev/null

# 4. Read Agent CSV to JSON (for easy parsing in python verifier)
cat > /tmp/csv_to_json.py << 'PYEOF'
import pandas as pd
import json
import sys

csv_path = "/home/ga/Documents/hec_ras_results/geometry_containment.csv"
try:
    if pd.io.common.file_exists(csv_path):
        df = pd.read_csv(csv_path)
        # Normalize columns
        df.columns = [c.lower().strip() for c in df.columns]
        result = df.to_dict(orient='records')
        print(json.dumps(result))
    else:
        print("[]")
except Exception:
    print("[]")
PYEOF

AGENT_CSV_DATA=$(python3 /tmp/csv_to_json.py 2>/dev/null)

# 5. Read Critical Sections JSON
AGENT_JSON_CONTENT="{}"
if [ -f "$JSON_FILE" ]; then
    AGENT_JSON_CONTENT=$(cat "$JSON_FILE")
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "files": {
        "csv_exists": $CSV_EXISTS,
        "json_exists": $JSON_EXISTS,
        "plot_exists": $PLOT_EXISTS
    },
    "agent_csv_data": $AGENT_CSV_DATA,
    "agent_critical_json": $AGENT_JSON_CONTENT,
    "ground_truth": $(cat /tmp/ground_truth_data.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"