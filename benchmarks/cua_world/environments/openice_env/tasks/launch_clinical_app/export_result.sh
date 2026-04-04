#!/bin/bash
echo "=== Exporting launch_clinical_app task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial state
INITIAL_WINDOWS=$(cat /tmp/initial_windows_list 2>/dev/null || echo "")
INITIAL_COUNT=$(echo "$INITIAL_WINDOWS" | wc -l)

# Get current state
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
FINAL_COUNT=$(echo "$FINAL_WINDOWS" | wc -l)

# Check OpenICE status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Check for app-related windows
APP_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "vital|xray|patient|infusion|clinical|app" | wc -l)

# Check for changes in window titles (app launched may change main window)
WINDOW_CHANGED="false"
if [ "$INITIAL_WINDOWS" != "$FINAL_WINDOWS" ]; then
    WINDOW_CHANGED="true"
fi

# Check logs for app launch activity
APP_LAUNCHED_LOG="false"
if grep -iE "app|application|launched|started|vital|xray|patient" /home/ga/openice/logs/openice.log 2>/dev/null | tail -20 > /dev/null 2>&1; then
    APP_LAUNCHED_LOG="true"
fi

# Evidence of app interaction
APP_INTERACTION="false"
if [ $FINAL_COUNT -ne $INITIAL_COUNT ] || [ "$WINDOW_CHANGED" = "true" ]; then
    APP_INTERACTION="true"
fi

# Create result JSON
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_window_count": $INITIAL_COUNT,
    "final_window_count": $FINAL_COUNT,
    "app_related_windows": $APP_WINDOWS,
    "openice_running": $OPENICE_RUNNING,
    "window_changed": $WINDOW_CHANGED,
    "app_launched_log": $APP_LAUNCHED_LOG,
    "app_interaction": $APP_INTERACTION,
    "final_windows": "$(echo "$FINAL_WINDOWS" | tr '\n' '|' | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Result exported ==="
echo "OpenICE running: $OPENICE_RUNNING"
echo "App interaction: $APP_INTERACTION"
echo "Window changed: $WINDOW_CHANGED"
cat /tmp/task_result.json
