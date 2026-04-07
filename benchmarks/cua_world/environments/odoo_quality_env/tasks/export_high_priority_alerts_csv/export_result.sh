#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DOWNLOADS_DIR="/home/ga/Downloads"

# Find the most recently modified CSV file in Downloads
# ls -t sorts by modification time, newest first
LATEST_CSV=$(ls -t "$DOWNLOADS_DIR"/*.csv 2>/dev/null | head -n 1)

CSV_EXISTS="false"
CSV_FILENAME=""
CSV_CONTENT=""
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$LATEST_CSV" ]; then
    CSV_EXISTS="true"
    CSV_FILENAME=$(basename "$LATEST_CSV")
    FILE_SIZE=$(stat -c %s "$LATEST_CSV" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$LATEST_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read content (base64 encode to safely transport via JSON if needed, 
    # but for simple CSV text, simple escaping usually suffices. 
    # Here we'll read raw and python will handle JSON escaping in the heredoc construction carefully,
    # or better: use python to construct the JSON to avoid shell escaping hell)
else
    echo "No CSV file found in $DOWNLOADS_DIR"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to construct the result JSON to handle file content escaping safely
python3 << PYTHON_EOF
import json
import os
import glob

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": False,
    "csv_filename": "",
    "csv_content": "",
    "file_created_during_task": False,
    "file_size_bytes": 0
}

latest_csv = "$LATEST_CSV"
if latest_csv and os.path.exists(latest_csv):
    result["csv_exists"] = True
    result["csv_filename"] = os.path.basename(latest_csv)
    result["file_size_bytes"] = os.path.getsize(latest_csv)
    
    # Check creation time vs task start
    mtime = os.path.getmtime(latest_csv)
    if mtime > $TASK_START:
        result["file_created_during_task"] = True
        
    try:
        with open(latest_csv, 'r', encoding='utf-8', errors='replace') as f:
            result["csv_content"] = f.read()
    except Exception as e:
        result["csv_content"] = f"Error reading file: {str(e)}"

# Save to temp file
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f)
PYTHON_EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="