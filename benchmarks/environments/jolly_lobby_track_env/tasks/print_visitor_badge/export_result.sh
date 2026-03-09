#!/bin/bash
set -e
echo "=== Exporting Print Visitor Badge Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence)
take_screenshot /tmp/task_final.png

# 2. Collect Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check for Output Files
PDF_PATH="/home/ga/Documents/visitor_badge_output.pdf"
PNG_PATH="/home/ga/Documents/visitor_badge_preview.png"

PDF_EXISTS="false"
PDF_SIZE="0"
PDF_CREATED_DURING="false"

PNG_EXISTS="false"
PNG_SIZE="0"
PNG_CREATED_DURING="false"

# Check PDF
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c%s "$PDF_PATH")
    FILE_TIME=$(stat -c%Y "$PDF_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING="true"
    fi
fi

# Check PNG
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c%s "$PNG_PATH")
    FILE_TIME=$(stat -c%Y "$PNG_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING="true"
    fi
fi

# 4. Check Application State
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# 5. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "pdf_created_during_task": $PDF_CREATED_DURING,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_created_during_task": $PNG_CREATED_DURING,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"