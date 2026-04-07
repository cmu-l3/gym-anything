#!/bin/bash
echo "=== Exporting open_wrench_head result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths to expected outputs
SLVS_PATH="/home/ga/Documents/SolveSpace/wrench_head.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/wrench_head.stl"

# Function to check file status
check_file() {
    local filepath="$1"
    local prefix="$2"
    
    if [ -f "$filepath" ]; then
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local created="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created="true"
        fi
        echo "\"${prefix}_exists\": true, \"${prefix}_size\": $size, \"${prefix}_created_during_task\": $created,"
    else
        echo "\"${prefix}_exists\": false, \"${prefix}_size\": 0, \"${prefix}_created_during_task\": false,"
    fi
}

# Check both files
SLVS_INFO=$(check_file "$SLVS_PATH" "slvs")
STL_INFO=$(check_file "$STL_PATH" "stl")

# Check if SolveSpace was running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    $SLVS_INFO
    $STL_INFO
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="