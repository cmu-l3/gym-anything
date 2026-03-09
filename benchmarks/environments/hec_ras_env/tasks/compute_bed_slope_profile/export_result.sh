#!/bin/bash
echo "=== Exporting compute_bed_slope_profile result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Basic Metadata
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/hec_ras_results/bed_slope_profile.csv"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"

# 2. Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Generate Ground Truth (using container's python/libraries)
# We calculate the expected values directly from the HDF file to compare with agent's output
echo "Generating ground truth from HDF5..."
cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys
import os

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
output_json = "/tmp/ground_truth.json"

try:
    if not os.path.exists(hdf_path):
        print(json.dumps({"error": "HDF file not found"}))
        sys.exit(0)

    with h5py.File(hdf_path, 'r') as f:
        # Navigate HEC-RAS geometry structure
        # Typical path: /Geometry/Cross Sections/
        if 'Geometry' not in f or 'Cross Sections' not in f['Geometry']:
            print(json.dumps({"error": "Geometry/Cross Sections path not found"}))
            sys.exit(0)
            
        xs_group = f['Geometry']['Cross Sections']
        
        # Get attributes (River Stations, Reach Lengths, etc.)
        # The structure varies by version, but often:
        # Attributes dataset contains [RiverStation, LeftBank, RightBank, ReachLenChnl, ...]
        # Or they are stored in specific datasets like 'River Stations', 'Reach Lengths'
        
        # Let's look for River Stations
        if 'River Stations' in xs_group:
            river_stations = xs_group['River Stations'][:]
            # Decode bytes if needed
            river_stations = [r.decode('utf-8') if isinstance(r, bytes) else str(r) for r in river_stations]
        elif 'Attributes' in xs_group:
            # Fallback parsing if needed, but modern RAS HDF has named datasets
            # Trying to be robust - if specific datasets exist
            pass
            
        # Extract Thalwegs
        thalwegs = []
        stations = []
        
        # Iterate over keys looking for coordinate data, or use 'Station Elevation Data'
        # Often structured as: /Geometry/Cross Sections/Station Elevation Data
        # Which is a 2D array or mapped via 'Station Elevation Info'
        
        # Easier approach for RAS HDF: 
        # /Geometry/Cross Sections/Station Elevation Data usually holds the points.
        # /Geometry/Cross Sections/Station Elevation Info holds [StartIndex, Count, ...]
        
        if 'Station Elevation Data' in xs_group and 'Station Elevation Info' in xs_group:
            se_data = xs_group['Station Elevation Data'][:] # [Station, Elevation]
            se_info = xs_group['Station Elevation Info'][:] # [StartIndex, Count, ...]
            river_stations_ds = xs_group['River Stations'][:]
            
            for i, info in enumerate(se_info):
                start_idx = int(info[0])
                count = int(info[1])
                
                # Get points for this XS
                xs_points = se_data[start_idx : start_idx + count]
                elevations = xs_points[:, 1]
                min_elev = float(np.min(elevations))
                
                rs_name = river_stations_ds[i].decode('utf-8')
                stations.append(rs_name)
                thalwegs.append(min_elev)
        
        # Get Reach Lengths (Downstream distance)
        # /Geometry/Cross Sections/Attributes often has columns. 
        # Or /Geometry/Cross Sections/Reach Lengths
        reach_lengths = []
        if 'Reach Lengths' in xs_group:
            # Typically [Left, Channel, Right]
            rl_data = xs_group['Reach Lengths'][:]
            # Assume column 1 is channel (index 1) if 2D, or look for 1D
            if rl_data.ndim == 2 and rl_data.shape[1] >= 2:
                reach_lengths = rl_data[:, 1].tolist() # Channel
            else:
                reach_lengths = rl_data.tolist()
        
        # Calculate Slopes
        results = []
        for i in range(len(stations)):
            rs = stations[i]
            z = thalwegs[i]
            
            # Downstream distance and slope calculation
            # RAS usually stores the reach length 'L' at section i as the distance to i+1 (downstream)
            dist = 0.0
            slope = None
            
            if i < len(reach_lengths):
                dist = float(reach_lengths[i])
                if dist > 0 and i < len(stations) - 1:
                    z_next = thalwegs[i+1]
                    slope = (z - z_next) / dist
            
            results.append({
                "river_station": rs,
                "thalweg_elevation": z,
                "downstream_distance": dist,
                "bed_slope": slope if slope is not None else "NaN"
            })
            
        with open(output_json, 'w') as out:
            json.dump({"cross_sections": results, "count": len(results)}, out)
            
except Exception as e:
    with open(output_json, 'w') as out:
        json.dump({"error": str(e)}, out)
EOF

# Execute the ground truth generator
python3 /tmp/generate_ground_truth.py

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
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

# Move output JSON to expected location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Ensure permissions for files we want to copy out
if [ -f "/tmp/ground_truth.json" ]; then
    chmod 666 /tmp/ground_truth.json
fi
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/agent_output.csv
    chmod 666 /tmp/agent_output.csv
fi

echo "Result generation complete"