#!/bin/bash
echo "=== Exporting analyze_reach_geometry result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_CSV="/home/ga/Documents/hec_ras_results/reach_stats.csv"
RESULT_SCRIPT="/home/ga/Documents/hec_ras_results/geometry_analysis.py"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file status
CSV_EXISTS="false"
SCRIPT_EXISTS="false"
CSV_CREATED_DURING_TASK="false"

if [ -f "$RESULT_CSV" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$RESULT_CSV" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$RESULT_SCRIPT" ]; then
    SCRIPT_EXISTS="true"
fi

# 3. Generate Ground Truth (using python inside container where libs are guaranteed)
# We generate a reference CSV to compare against
cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import pandas as pd
import os
import sys

# Try to find the HDF file
project_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
hdf_file = None
for f in os.listdir(project_dir):
    if f.endswith(".hdf") and "p04" in f:
        hdf_file = os.path.join(project_dir, f)
        break

if not hdf_file or not os.path.exists(hdf_file):
    print("No HDF file found for ground truth generation")
    sys.exit(0)

try:
    with h5py.File(hdf_file, 'r') as f:
        # Access Geometry paths (standard RAS HDF structure)
        # Note: Structure can vary, trying standard paths
        geom_path = 'Geometry/Cross Sections'
        
        # Get River Stations
        rs_path = f'{geom_path}/River Stations'
        if rs_path in f:
            river_stations = [x.decode('utf-8').strip() for x in f[rs_path][:]]
        else:
            # Fallback to attributes if available
            river_stations = []

        # Get Reach Lengths (Channel is usually index 1 in the lengths array)
        # Lengths are often stored in 'Lengths' dataset or 'Attributes'
        lengths = []
        if f'{geom_path}/Lengths' in f:
            # Shape is usually (N, 3) -> LOB, Channel, ROB
            lengths_data = f[f'{geom_path}/Lengths'][:]
            lengths = lengths_data[:, 1] # Channel length
        
        # Get Inverts (Min elevation)
        inverts = []
        # Need to iterate through each XS to find min elevation
        # Dataset names are often "Station Elevation Info" or under a group
        
        # Alternative: use 'Attributes' table if it exists, it often has min elev
        # But let's try to compute from raw coords if possible or look for summary
        
        # For this ground truth script, we'll try to extract what we can
        # If specific paths aren't found, we'll output empty and verifier will handle
        
        rows = []
        # Assuming we have N stations and N lengths (length i is distance to i+1)
        # We process N-1 intervals
        
        # We need inverts. Let's look for "Minimum Channel Elevation" in Attributes if present
        # Or iterate Station Elevation groups
        
        # Simpler approach for verification:
        # We will export the raw River Stations and Lengths we found
        # The verifier will primarily check MATH CONSISTENCY of the agent's file
        # rather than exact matching against a complex ground truth generation here.
        # But we will save what we found.
        
        df = pd.DataFrame({
            'RS': river_stations,
            'Channel_Length': lengths if len(lengths) == len(river_stations) else [0]*len(river_stations)
        })
        df.to_csv('/tmp/ground_truth_partial.csv', index=False)
        print("Ground truth generated")

except Exception as e:
    print(f"Error generating ground truth: {e}")
PYEOF

python3 /tmp/generate_ground_truth.py > /tmp/gt_gen.log 2>&1

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move files for export
# Move JSON
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Move Agent CSV
rm -f /tmp/agent_reach_stats.csv 2>/dev/null || true
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$RESULT_CSV" /tmp/agent_reach_stats.csv
    chmod 666 /tmp/agent_reach_stats.csv
fi

# Move Ground Truth CSV
rm -f /tmp/ground_truth.csv 2>/dev/null || true
if [ -f /tmp/ground_truth_partial.csv ]; then
    cp /tmp/ground_truth_partial.csv /tmp/ground_truth.csv
    chmod 666 /tmp/ground_truth.csv
fi

# Move Agent Script
rm -f /tmp/agent_script.py 2>/dev/null || true
if [ "$SCRIPT_EXISTS" = "true" ]; then
    cp "$RESULT_SCRIPT" /tmp/agent_script.py
    chmod 666 /tmp/agent_script.py
fi

echo "Export complete."
cat /tmp/task_result.json