#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
FCSTD_PATH="/home/ga/Documents/FreeCAD/T8_housing_cnc.FCStd"
GCODE_PATH="/home/ga/Documents/FreeCAD/T8_housing.nc"

# Check FCStd file
if [ -f "$FCSTD_PATH" ]; then
    FCSTD_EXISTS="true"
    FCSTD_SIZE=$(stat -c %s "$FCSTD_PATH" 2>/dev/null || echo "0")
    FCSTD_MTIME=$(stat -c %Y "$FCSTD_PATH" 2>/dev/null || echo "0")
    
    if [ "$FCSTD_MTIME" -gt "$TASK_START" ]; then
        FCSTD_CREATED_DURING_TASK="true"
    else
        FCSTD_CREATED_DURING_TASK="false"
    fi
else
    FCSTD_EXISTS="false"
    FCSTD_SIZE="0"
    FCSTD_CREATED_DURING_TASK="false"
fi

# Check G-code file
if [ -f "$GCODE_PATH" ]; then
    GCODE_EXISTS="true"
    GCODE_SIZE=$(stat -c %s "$GCODE_PATH" 2>/dev/null || echo "0")
    GCODE_MTIME=$(stat -c %Y "$GCODE_PATH" 2>/dev/null || echo "0")
    
    if [ "$GCODE_MTIME" -gt "$TASK_START" ]; then
        GCODE_CREATED_DURING_TASK="true"
    else
        GCODE_CREATED_DURING_TASK="false"
    fi
else
    GCODE_EXISTS="false"
    GCODE_SIZE="0"
    GCODE_CREATED_DURING_TASK="false"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_size": $FCSTD_SIZE,
    "fcstd_created_during_task": $FCSTD_CREATED_DURING_TASK,
    "gcode_exists": $GCODE_EXISTS,
    "gcode_size": $GCODE_SIZE,
    "gcode_created_during_task": $GCODE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "fcstd_path": "$FCSTD_PATH",
    "gcode_path": "$GCODE_PATH"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="