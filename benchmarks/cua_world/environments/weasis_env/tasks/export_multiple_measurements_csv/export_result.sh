#!/bin/bash
echo "=== Exporting export_multiple_measurements_csv result ==="

# Take final screenshot before stopping services
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/DICOM/exports/trial_data.csv"
SCREENSHOT_PATH="/home/ga/DICOM/exports/trial_screenshot.jpg"

# Fallback checking for different image extensions if the agent used a different one
if [ ! -f "$SCREENSHOT_PATH" ]; then
    if [ -f "/home/ga/DICOM/exports/trial_screenshot.jpeg" ]; then
        SCREENSHOT_PATH="/home/ga/DICOM/exports/trial_screenshot.jpeg"
    elif [ -f "/home/ga/DICOM/exports/trial_screenshot.png" ]; then
        SCREENSHOT_PATH="/home/ga/DICOM/exports/trial_screenshot.png"
    fi
fi

# Inspect CSV file
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Inspect Screenshot file
IMG_EXISTS="false"
IMG_SIZE=0
IMG_CREATED_DURING_TASK="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    IMG_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING_TASK="true"
    fi
fi

APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size": $CSV_SIZE,
    "csv_internal_path": "$CSV_PATH",
    "img_exists": $IMG_EXISTS,
    "img_created_during_task": $IMG_CREATED_DURING_TASK,
    "img_size": $IMG_SIZE,
    "img_internal_path": "$SCREENSHOT_PATH"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="