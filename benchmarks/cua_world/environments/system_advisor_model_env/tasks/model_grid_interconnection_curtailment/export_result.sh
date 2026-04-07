#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

JSON_FILE="/home/ga/Documents/SAM_Projects/curtailment_results.json"
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/curtailment_analysis.py"

JSON_EXISTS="false"
JSON_MODIFIED="false"
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"

# Verify existence and creation time of the expected JSON output
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Verify existence and creation time of the Python analysis script
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_modified "$SCRIPT_MODIFIED" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        json_exists: $json_exists,
        json_modified: $json_modified,
        script_exists: $script_exists,
        script_modified: $script_modified,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="