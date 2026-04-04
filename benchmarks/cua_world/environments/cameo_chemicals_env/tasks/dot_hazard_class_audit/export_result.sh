#!/bin/bash
echo "=== Exporting DOT Hazard Class Audit Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
OUTPUT_FILE="/home/ga/Documents/manifest_audit_report.csv"
FINAL_SCREENSHOT="/tmp/task_final.png"

# 1. Capture Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || \
    DISPLAY=:1 import -window root "$FINAL_SCREENSHOT" 2>/dev/null || true

# 2. Check Output File Status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE_BYTES=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Prepare Result JSON
# We do NOT put the file content in JSON; the verifier will pull the file itself.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE_BYTES,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "$FINAL_SCREENSHOT"
}
EOF

# 5. Save JSON to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="