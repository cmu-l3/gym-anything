#!/bin/bash
echo "=== Exporting export_clean_and_annotated_views task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/DICOM/exports"
ANNOTATED_FILE="$EXPORT_DIR/annotated.jpg"
CLEAN_FILE="$EXPORT_DIR/clean.jpg"

ANNOTATED_EXISTS="false"
ANNOTATED_MTIME=0
ANNOTATED_SIZE=0
CLEAN_EXISTS="false"
CLEAN_MTIME=0
CLEAN_SIZE=0

if [ -f "$ANNOTATED_FILE" ]; then
    ANNOTATED_EXISTS="true"
    ANNOTATED_MTIME=$(stat -c %Y "$ANNOTATED_FILE" 2>/dev/null || echo "0")
    ANNOTATED_SIZE=$(stat -c %s "$ANNOTATED_FILE" 2>/dev/null || echo "0")
fi

if [ -f "$CLEAN_FILE" ]; then
    CLEAN_EXISTS="true"
    CLEAN_MTIME=$(stat -c %Y "$CLEAN_FILE" 2>/dev/null || echo "0")
    CLEAN_SIZE=$(stat -c %s "$CLEAN_FILE" 2>/dev/null || echo "0")
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "annotated_file": {
        "exists": $ANNOTATED_EXISTS,
        "mtime": $ANNOTATED_MTIME,
        "size_bytes": $ANNOTATED_SIZE,
        "path": "$ANNOTATED_FILE"
    },
    "clean_file": {
        "exists": $CLEAN_EXISTS,
        "mtime": $CLEAN_MTIME,
        "size_bytes": $CLEAN_SIZE,
        "path": "$CLEAN_FILE"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="