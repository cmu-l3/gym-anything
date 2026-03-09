#!/bin/bash
echo "=== Exporting Nuclei Motility Results ==="

# Define paths
RESULTS_DIR="/home/ga/Fiji_Data/results/tracking"
CSV_PATH="$RESULTS_DIR/track_statistics.csv"
VISUAL_PATH="$RESULTS_DIR/tracks_visual.png"
JSON_OUTPUT="/tmp/tracking_result.json"
TASK_START_FILE="/tmp/task_start_time"

# Get task start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to check file modification time
check_file_modified() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

# Analyze results using embedded Python
python3 << PYEOF
import os
import json
import csv
import sys

csv_path = "$CSV_PATH"
visual_path = "$VISUAL_PATH"
task_start = int("$TASK_START")

result = {
    "csv_exists": False,
    "csv_valid": False,
    "track_count": 0,
    "has_motion_data": False,
    "mean_speed": 0.0,
    "visual_exists": False,
    "visual_size": 0,
    "files_created_during_task": False
}

# Check CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    # Check if created during task
    if os.path.getmtime(csv_path) > task_start:
        result["files_created_during_task"] = True
        
    try:
        with open(csv_path, 'r', encoding='utf-8-sig') as f:
            # Read header
            # TrackMate exports can have comments at top
            lines = f.readlines()
            data_lines = [l for l in lines if not l.startswith('#')]
            
            if len(data_lines) > 1:
                # Try to parse
                reader = csv.DictReader(data_lines)
                rows = list(reader)
                
                if len(rows) > 0:
                    result["csv_valid"] = True
                    result["track_count"] = len(rows)
                    
                    # Normalize keys to find speed
                    keys = rows[0].keys()
                    speed_key = next((k for k in keys if 'SPEED' in k.upper() or 'VELOCITY' in k.upper()), None)
                    
                    if speed_key:
                        speeds = []
                        for r in rows:
                            try:
                                val = float(r[speed_key])
                                speeds.append(val)
                            except:
                                pass
                        
                        if speeds:
                            result["has_motion_data"] = True
                            result["mean_speed"] = sum(speeds) / len(speeds)

    except Exception as e:
        print(f"Error parsing CSV: {e}", file=sys.stderr)

# Check Visual
if os.path.exists(visual_path):
    result["visual_exists"] = True
    result["visual_size"] = os.path.getsize(visual_path)
    if os.path.getmtime(visual_path) > task_start:
        result["files_created_during_task"] = True

# Also check for TIF visual if PNG missing
if not result["visual_exists"]:
    tif_path = visual_path.replace('.png', '.tif')
    if os.path.exists(tif_path):
        result["visual_exists"] = True
        result["visual_size"] = os.path.getsize(tif_path)

with open("$JSON_OUTPUT", 'w') as f:
    json.dump(result, f)

print("Analysis complete.")
PYEOF

# Set permissions for the result file so verification script can read it
chmod 644 "$JSON_OUTPUT" 2>/dev/null || true

echo "Export complete. Result saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"