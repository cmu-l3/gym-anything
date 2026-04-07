#!/bin/bash
echo "=== Exporting recist_tumor_measurement task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing application
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"

REPORT_PATH="$EXPORT_DIR/recist_report.txt"
SCREENSHOT_PATH="$EXPORT_DIR/recist_annotation.png"

# Process report text validation variables
REPORT_EXISTS="false"
REPORT_CREATED="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED="true"
    fi
fi

# Process agent screenshot variables
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED="false"
SCREENSHOT_SIZE="0"
if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED="true"
    fi
fi

APP_RUNNING="false"
if pgrep -f weasis > /dev/null; then
    APP_RUNNING="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created": $REPORT_CREATED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created": $SCREENSHOT_CREATED,
    "screenshot_size": $SCREENSHOT_SIZE
}
EOF

# Move and set permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="