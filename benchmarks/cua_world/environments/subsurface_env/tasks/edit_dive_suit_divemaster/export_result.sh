#!/bin/bash
set -e
echo "=== Exporting edit_dive_suit_divemaster result ==="

# Record task end time and retrieve initial state data
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/ssrf_initial_dive_count.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/dives.ssrf"

# Determine if the user actually modified and saved the file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" != "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED="false"
    OUTPUT_MTIME="0"
fi

# Take a final screenshot for the VLM check
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# Create JSON result object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_mtime": $INITIAL_MTIME,
    "output_mtime": $OUTPUT_MTIME,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "initial_dive_count": $INITIAL_COUNT
}
EOF

# Move to the final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="