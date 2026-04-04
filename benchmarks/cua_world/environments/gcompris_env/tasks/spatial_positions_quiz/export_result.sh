#!/bin/bash
echo "=== Exporting Spatial Positions Quiz results ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Check evidence files
FILE_QUESTION="/home/ga/Documents/positions_question.png"
FILE_SUCCESS="/home/ga/Documents/positions_success.png"

check_file() {
    local path=$1
    local exists="false"
    local created_in_task="false"
    local size=0
    
    if [ -f "$path" ]; then
        exists="true"
        size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_in_task="true"
        fi
    fi
    
    echo "\"exists\": $exists, \"created_in_task\": $created_in_task, \"size\": $size"
}

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "evidence_question": { $(check_file "$FILE_QUESTION") },
    "evidence_success": { $(check_file "$FILE_SUCCESS") },
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="