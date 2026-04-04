#!/bin/bash
echo "=== Exporting scale_and_export_stl result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check STL Output
STL_PATH="/home/ga/Documents/nrel_5mw_model_1m.stl"
STL_EXISTS="false"
STL_SIZE=0
STL_CREATED_DURING_TASK="false"

if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
    STL_MTIME=$(stat -c %Y "$STL_PATH" 2>/dev/null || echo "0")
    
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Project Output
WPA_PATH="/home/ga/Documents/projects/nrel_5mw_scaled.wpa"
WPA_EXISTS="false"
WPA_SIZE=0
WPA_CREATED_DURING_TASK="false"

if [ -f "$WPA_PATH" ]; then
    WPA_EXISTS="true"
    WPA_SIZE=$(stat -c %s "$WPA_PATH" 2>/dev/null || echo "0")
    WPA_MTIME=$(stat -c %Y "$WPA_PATH" 2>/dev/null || echo "0")
    
    if [ "$WPA_MTIME" -gt "$TASK_START" ]; then
        WPA_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check App Status
APP_RUNNING=$(is_qblade_running)
if [ "$APP_RUNNING" -gt 0 ]; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f "/tmp/task_final.png" ] && SCREENSHOT_EXISTS="true"

# 5. Create JSON Result
# Use temp file for permission safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "stl_exists": $STL_EXISTS,
    "stl_path": "$STL_PATH",
    "stl_size": $STL_SIZE,
    "stl_created_during_task": $STL_CREATED_DURING_TASK,
    "wpa_exists": $WPA_EXISTS,
    "wpa_path": "$WPA_PATH",
    "wpa_size": $WPA_SIZE,
    "wpa_created_during_task": $WPA_CREATED_DURING_TASK,
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