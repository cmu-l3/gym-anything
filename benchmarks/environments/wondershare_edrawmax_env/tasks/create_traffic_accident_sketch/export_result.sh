#!/bin/bash
echo "=== Exporting create_traffic_accident_sketch results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EDDX_PATH="/home/ga/Documents/accident_sketch_2024_891.eddx"
PDF_PATH="/home/ga/Documents/accident_sketch_2024_891.pdf"

# Check EDDX file
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    else
        EDDX_CREATED_DURING_TASK="false"
    fi
else
    EDDX_EXISTS="false"
    EDDX_SIZE="0"
    EDDX_CREATED_DURING_TASK="false"
fi

# Check PDF file
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    else
        PDF_CREATED_DURING_TASK="false"
    fi
else
    PDF_EXISTS="false"
    PDF_SIZE="0"
    PDF_CREATED_DURING_TASK="false"
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "EdrawMax" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING_TASK,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "pdf_created_during_task": $PDF_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="