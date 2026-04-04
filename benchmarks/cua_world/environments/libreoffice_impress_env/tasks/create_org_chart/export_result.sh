#!/bin/bash
echo "=== Exporting Create Org Chart Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WORK_DIR="/home/ga/Documents/Presentations"

# Identify the target file (could be .pptx or .odp)
# We look for the most recently modified presentation file
TARGET_FILE=""
LATEST_TIME=0

# Check common file locations
for f in "$WORK_DIR/acme_annual_review.pptx" \
         "$WORK_DIR/acme_annual_review.odp" \
         "$WORK_DIR"/*.pptx \
         "$WORK_DIR"/*.odp; do
    if [ -f "$f" ]; then
        M_TIME=$(stat -c %Y "$f")
        if [ "$M_TIME" -gt "$LATEST_TIME" ]; then
            LATEST_TIME=$M_TIME
            TARGET_FILE="$f"
        fi
    fi
done

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_PATH=""
FILE_SIZE="0"

if [ -n "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_PATH="$TARGET_FILE"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    
    # Check if modified during task
    if [ "$LATEST_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if Impress is running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$FILE_PATH",
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="