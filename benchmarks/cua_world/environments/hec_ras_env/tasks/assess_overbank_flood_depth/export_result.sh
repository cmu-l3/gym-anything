#!/bin/bash
echo "=== Exporting assess_overbank_flood_depth results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/overbank_depth_assessment.csv"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Generate Ground Truth (using container's python/h5py)
# We do this here to avoid HDF library compatibility issues on the verifier host
echo "Generating ground truth data..."
cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import os

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
output_path = "/tmp/ground_truth.json"

try:
    if not os.path.exists(hdf_path):
        print(f"Error: HDF file not found at {hdf_path}")
        exit(1)

    with h5py.File(hdf_path, 'r') as f:
        # Access Geometry
        geom_path = 'Geometry/Cross Sections'
        if geom_path not in f:
            # Fallback for some HEC-RAS versions
            geom_path = 'Geometry/2D Flow Areas' 
            # Note: This task targets 1D XS, assuming Muncie 1D structure
        
        # Get River Stations
        # River Stations are often stored as byte strings in 'River Stations' dataset
        # Paths vary by HEC-RAS version. Standard v6+ path:
        xs_base = f['Geometry/Cross Sections']
        river_stations_raw = xs_base['River Stations'][:]
        river_stations = [rs.decode('utf-8').strip() for rs in river_stations_raw]
        
        # Create a list of (index, numeric_value, original_string)
        # Assuming numeric stations for sorting
        rs_data = []
        for i, rs in enumerate(river_stations):
            try:
                val = float(rs)
                rs_data.append({'index': i, 'val': val, 'str': rs})
            except:
                pass # Skip non-numeric if any
        
        # Sort descending (upstream -> downstream)
        rs_data.sort(key=lambda x: x['val'], reverse=True)
        
        # Take top 5 upstream
        target_xs = rs_data[:5]
        
        ground_truth = []
        
        # Get Bank Stations
        bank_stations = xs_base['Bank Stations'][:] # Shape (N, 2) usually [Left, Right]
        
        # Get Max WSE (Results)
        # Path: /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
        # Dataset shape: (Time, XS) -> we want Max over time
        wse_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'
        wse_data = f[wse_path][:] # Shape (Time, XS)
        max_wse_all = np.max(wse_data, axis=0)
        
        for xs in target_xs:
            idx = xs['index']
            rs_str = xs['str']
            
            # 1. Left Bank Station
            lbs = bank_stations[idx][0]
            if np.isnan(lbs): 
                # Fallback check attributes if needed, but array usually valid
                lbs = 0.0 
            
            # 2. Target Station
            target_station = lbs - 50.0
            
            # 3. Interpolate Ground
            # Coordinates are stored in 'Station Elevation' usually
            # But in HDF, often flattened or indexed. 
            # Look for 'Station Elevation Info' (Start Index, Count)
            # and 'Station Elevation Values' (Station, Elev)
            
            info = xs_base['Station Elevation Info'][idx] # [Start, Count]
            start = info[0]
            count = info[1]
            
            coords = xs_base['Station Elevation Values'][start:start+count] # Shape (M, 2)
            stations = coords[:, 0]
            elevations = coords[:, 1]
            
            # Linear Interpolation
            ground_elev = np.interp(target_station, stations, elevations, left=np.nan, right=np.nan)
            
            # 4. Max WSE
            max_wse = max_wse_all[idx]
            
            # 5. Depth
            depth = 0.0
            if not np.isnan(ground_elev):
                depth = max_wse - ground_elev
                if depth < 0:
                    depth = 0.0
            
            ground_truth.append({
                "river_station": rs_str,
                "left_bank_station": float(lbs),
                "target_station": float(target_station),
                "ground_elev": float(ground_elev) if not np.isnan(ground_elev) else -999.0,
                "max_wse": float(max_wse),
                "flood_depth": float(depth)
            })
            
    with open(output_path, 'w') as out:
        json.dump(ground_truth, out, indent=2)
    
    print(f"Ground truth generated for {len(ground_truth)} stations.")

except Exception as e:
    print(f"Generator Error: {e}")
    # Write empty array on fail
    with open(output_path, 'w') as out:
        json.dump([], out)
EOF

python3 /tmp/generate_ground_truth.py
echo "Ground truth saved to /tmp/ground_truth.json"

# 4. Check outputs
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_path": "$CSV_PATH",
    "ground_truth_path": "/tmp/ground_truth.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="