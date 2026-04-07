#!/bin/bash
echo "=== Exporting data_unit_reverse_mapping results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Reports/block_tracing_report.csv"

# Check if output file exists and was modified during task
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Read up to 10KB of content to prevent huge file payloads
    FILE_CONTENT=$(head -c 10000 "$OUTPUT_PATH" | tr -d '\000')
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
    FILE_CONTENT=""
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Safely encode the file content to JSON using Python
python3 << PYEOF
import json
import os

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": ${OUTPUT_EXISTS},
    "file_created_during_task": ${FILE_CREATED_DURING_TASK},
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}

try:
    with open("$OUTPUT_PATH", "r", errors="replace") as f:
        result["file_content"] = f.read(10000)
except Exception:
    result["file_content"] = ""

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json."