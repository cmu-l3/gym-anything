#!/bin/bash
echo "=== Exporting model_angled_sensor_mount results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FCSTD_PATH="/home/ga/Documents/FreeCAD/sensor_mount.FCStd"
STL_PATH="/home/ga/Documents/FreeCAD/sensor_mount.stl"

# Function to check file status
check_file() {
    local path=$1
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true|$size"
        else
            echo "false|$size" # Exists but old
        fi
    else
        echo "false|0"
    fi
}

# Check files
IFS='|' read FCSTD_CREATED FCSTD_SIZE <<< $(check_file "$FCSTD_PATH")
IFS='|' read STL_CREATED STL_SIZE <<< $(check_file "$STL_PATH")

# Check if app is running
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "fcstd_exists": $([ -f "$FCSTD_PATH" ] && echo "true" || echo "false"),
    "fcstd_created_during_task": $FCSTD_CREATED,
    "fcstd_size": $FCSTD_SIZE,
    "stl_exists": $([ -f "$STL_PATH" ] && echo "true" || echo "false"),
    "stl_created_during_task": $STL_CREATED,
    "stl_size": $STL_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="