#!/bin/bash
echo "=== Exporting create_3d_nameplate results ==="

# 1. Define Paths
FCSTD_PATH="/home/ga/Documents/FreeCAD/nameplate.FCStd"
STL_PATH="/home/ga/Documents/FreeCAD/nameplate.stl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Check FCStd File
if [ -f "$FCSTD_PATH" ]; then
    FCSTD_EXISTS="true"
    FCSTD_SIZE=$(stat -c %s "$FCSTD_PATH")
    FCSTD_MTIME=$(stat -c %Y "$FCSTD_PATH")
    if [ "$FCSTD_MTIME" -gt "$TASK_START" ]; then
        FCSTD_CREATED_DURING="true"
    else
        FCSTD_CREATED_DURING="false"
    fi
else
    FCSTD_EXISTS="false"
    FCSTD_SIZE="0"
    FCSTD_CREATED_DURING="false"
fi

# 3. Check STL File
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_PATH")
    STL_MTIME=$(stat -c %Y "$STL_PATH")
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED_DURING="true"
    else
        STL_CREATED_DURING="false"
    fi
else
    STL_EXISTS="false"
    STL_SIZE="0"
    STL_CREATED_DURING="false"
fi

# 4. Check Application State
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# 5. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_size": $FCSTD_SIZE,
    "fcstd_created_during_task": $FCSTD_CREATED_DURING,
    "stl_exists": $STL_EXISTS,
    "stl_size": $STL_SIZE,
    "stl_created_during_task": $STL_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="