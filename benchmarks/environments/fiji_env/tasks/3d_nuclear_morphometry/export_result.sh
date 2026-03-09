#!/bin/bash
echo "=== Exporting 3D Nuclear Morphometry Results ==="

# Paths
CSV_PATH="/home/ga/Fiji_Data/results/3d_morphometry.csv"
MAP_PATH="/home/ga/Fiji_Data/results/3d_object_map.tif"
RESULT_JSON="/tmp/3d_morphometry_result.json"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Take Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Start Time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# 3. Analyze Results using Python
# We parse the CSV here to avoid needing complex file copying logic in the verifier
python3 << PYEOF
import json
import os
import csv
import sys

result = {
    "csv_exists": False,
    "map_exists": False,
    "csv_created_during_task": False,
    "map_created_during_task": False,
    "columns_found": [],
    "object_count": 0,
    "volume_values": [],
    "surface_values": [],
    "error": ""
}

csv_path = "$CSV_PATH"
map_path = "$MAP_PATH"
task_start = int("$TASK_START")

# Check Map File
if os.path.exists(map_path):
    result["map_exists"] = True
    if os.path.getmtime(map_path) > task_start:
        result["map_created_during_task"] = True

# Check CSV File
if os.path.exists(csv_path):
    result["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        result["csv_created_during_task"] = True
    
    try:
        with open(csv_path, 'r', encoding='utf-8-sig') as f:
            # Fiji CSVs often have headers. 3D Objects Counter usually has:
            # "Label", "Volume (unit)", "Surface (unit)", ...
            # sometimes just "Volume", "Surface" depending on version/settings
            reader = csv.reader(f)
            headers = next(reader, None)
            
            if headers:
                # Normalize headers to lowercase for checking
                result["columns_found"] = headers
                lower_headers = [h.lower() for h in headers]
                
                # Find column indices
                vol_idx = -1
                surf_idx = -1
                
                for i, col in enumerate(lower_headers):
                    if "vol" in col:
                        vol_idx = i
                    if "surf" in col:
                        surf_idx = i
                
                # Read Data
                count = 0
                volumes = []
                surfaces = []
                
                for row in reader:
                    if not row: continue
                    count += 1
                    if vol_idx != -1 and vol_idx < len(row):
                        try:
                            volumes.append(float(row[vol_idx]))
                        except ValueError:
                            pass
                    if surf_idx != -1 and surf_idx < len(row):
                        try:
                            surfaces.append(float(row[surf_idx]))
                        except ValueError:
                            pass
                
                result["object_count"] = count
                result["volume_values"] = volumes
                result["surface_values"] = surfaces
                
    except Exception as e:
        result["error"] = str(e)

# Write Result JSON
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# 4. Set Permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true
echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="