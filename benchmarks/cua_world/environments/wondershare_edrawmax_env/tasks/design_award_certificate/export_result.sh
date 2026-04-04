#!/bin/bash
echo "=== Exporting design_award_certificate results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
EDDX_PATH="/home/ga/Documents/certificate_jordan_lee.eddx"
PDF_PATH="/home/ga/Documents/certificate_jordan_lee.pdf"
PNG_PATH="/home/ga/Documents/certificate_jordan_lee.png"

# Function to check file details
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check all files
EDDX_INFO=$(check_file "$EDDX_PATH")
PDF_INFO=$(check_file "$PDF_PATH")
PNG_INFO=$(check_file "$PNG_PATH")

# Check if application was running
APP_RUNNING="false"
if is_edrawmax_running; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "files": {
        "eddx": $EDDX_INFO,
        "pdf": $PDF_INFO,
        "png": $PNG_INFO
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="