#!/bin/bash
echo "=== Exporting split_part_for_printing results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Collect timestamps and file info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

BOTTOM_FILE="/home/ga/Documents/FreeCAD/bracket_bottom.stl"
TOP_FILE="/home/ga/Documents/FreeCAD/bracket_top.stl"

# Helper to get file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during_task, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false, \"path\": \"$fpath\"}"
    fi
}

BOTTOM_INFO=$(get_file_info "$BOTTOM_FILE")
TOP_INFO=$(get_file_info "$TOP_FILE")

# 3. Check if FreeCAD is still running
APP_RUNNING="false"
if pgrep -f "FreeCAD" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "bottom_file": $BOTTOM_INFO,
    "top_file": $TOP_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to shared location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="