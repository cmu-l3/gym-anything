#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
SLVS_PATH="/home/ga/Documents/SolveSpace/spacer.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/spacer.stl"

# Function to check file existence and modification time
check_file() {
    local path=$1
    local prefix=$2
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local created="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created="true"
        fi
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        echo "\"${prefix}_exists\": true, \"${prefix}_created_during_task\": $created, \"${prefix}_size_bytes\": $size,"
    else
        echo "\"${prefix}_exists\": false, \"${prefix}_created_during_task\": false, \"${prefix}_size_bytes\": 0,"
    fi
}

# Take final screenshot for VLM checks
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "\"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "\"task_end\": $TASK_END," >> "$TEMP_JSON"
check_file "$SLVS_PATH" "slvs" >> "$TEMP_JSON"
check_file "$STL_PATH" "stl" >> "$TEMP_JSON"
echo "\"app_was_running\": $APP_RUNNING," >> "$TEMP_JSON"
echo "\"screenshot_path\": \"/tmp/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="