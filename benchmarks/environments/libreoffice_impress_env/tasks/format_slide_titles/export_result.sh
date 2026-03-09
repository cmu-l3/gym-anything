#!/bin/bash
echo "=== Exporting format_slide_titles result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "0")

# Identify the output file (could be pptx or odp)
PRES_DIR="/home/ga/Documents/Presentations"
RESULT_FILE=""
FILE_FORMAT=""

# Check for modified PPTX
if [ -f "$PRES_DIR/staff_meeting.pptx" ]; then
    # Check if modified after start
    MTIME=$(stat -c %Y "$PRES_DIR/staff_meeting.pptx" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        RESULT_FILE="$PRES_DIR/staff_meeting.pptx"
        FILE_FORMAT="pptx"
    fi
fi

# If pptx not modified, check for new ODP
if [ -z "$RESULT_FILE" ]; then
    if [ -f "$PRES_DIR/staff_meeting.odp" ]; then
        MTIME=$(stat -c %Y "$PRES_DIR/staff_meeting.odp" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            RESULT_FILE="$PRES_DIR/staff_meeting.odp"
            FILE_FORMAT="odp"
        fi
    fi
fi

# Check file existence and hashing
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_HASH=""

if [ -n "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_HASH=$(md5sum "$RESULT_FILE" | awk '{print $1}')
    if [ "$FILE_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy result file to a temp location for easier retrieval by verifier
    # We rename it to a standard name for the verifier
    cp "$RESULT_FILE" /tmp/result_presentation.$FILE_FORMAT
    chmod 666 /tmp/result_presentation.$FILE_FORMAT
fi

# Check if Impress is still running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_format": "$FILE_FORMAT",
    "result_path": "/tmp/result_presentation.$FILE_FORMAT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="