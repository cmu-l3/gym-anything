#!/bin/bash
echo "=== Exporting Mitotic Spindle Tracking results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Fiji_Data/results/tracking/spindle_intensity.csv"

# 1. Check file existence and modification time
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    # Read content for JSON export (handled safely via Python below)
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_MTIME="0"
fi

# 2. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create JSON result
# We use Python to parse the CSV safely into the JSON
python3 << EOF
import json
import csv
import os

output_path = "$OUTPUT_PATH"
result = {
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_data": [],
    "errors": []
}

if result["output_exists"]:
    try:
        with open(output_path, 'r') as f:
            # Read locally, handle potential BOM or weird formats
            lines = [l.strip() for l in f.readlines() if l.strip()]
            
            # Simple CSV parsing
            reader = csv.reader(lines)
            headers = next(reader, [])
            
            # Normalize headers
            headers = [h.lower().strip() for h in headers]
            
            # Find columns
            try:
                frame_idx = -1
                intensity_idx = -1
                
                # Flexible header matching
                for i, h in enumerate(headers):
                    if 'frame' in h: frame_idx = i
                    if 'mean' in h or 'intensity' in h or 'val' in h: intensity_idx = i
                
                if frame_idx == -1: # Fallback: assume col 0 is frame
                    frame_idx = 0
                if intensity_idx == -1: # Fallback: assume col 1 is intensity
                    intensity_idx = 1
                    
                # Extract data
                for row in reader:
                    if len(row) > max(frame_idx, intensity_idx):
                        try:
                            f_val = int(float(row[frame_idx]))
                            i_val = float(row[intensity_idx])
                            result["csv_data"].append({"frame": f_val, "intensity": i_val})
                        except ValueError:
                            continue
            except Exception as e:
                result["errors"].append(f"Parsing error: {str(e)}")
                
    except Exception as e:
        result["errors"].append(f"File read error: {str(e)}")

# Save to temp file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="