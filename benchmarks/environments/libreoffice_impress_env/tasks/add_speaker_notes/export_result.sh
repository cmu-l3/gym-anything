#!/bin/bash
echo "=== Exporting Add Speaker Notes Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/Presentations/community_impact_report.odp"

# Check if application was running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Ensure file exists
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Copy the ODP file to tmp for the verifier to access via copy_from_env
# We rename it to generic task_result.odp to be safe
if [ -f "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" /tmp/task_result.odp
    chmod 666 /tmp/task_result.odp
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "odp_path": "/tmp/task_result.odp"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="