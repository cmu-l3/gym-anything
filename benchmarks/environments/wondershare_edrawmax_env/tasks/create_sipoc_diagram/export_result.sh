#!/bin/bash
echo "=== Exporting create_sipoc_diagram results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
EDDX_PATH="/home/ga/Documents/help_desk_sipoc.eddx"
PNG_PATH="/home/ga/Documents/help_desk_sipoc.png"

# Function to check file stats
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        # Check if created/modified during task
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "{\"exists\": true, \"size\": $size, \"created_during_task\": true}"
        else
            echo "{\"exists\": true, \"size\": $size, \"created_during_task\": false}"
        fi
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check files
EDDX_STATS=$(check_file "$EDDX_PATH")
PNG_STATS=$(check_file "$PNG_PATH")

# Check if application was running
APP_RUNNING=$(pgrep -f "EdrawMax" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_file": $EDDX_STATS,
    "png_file": $PNG_STATS,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="