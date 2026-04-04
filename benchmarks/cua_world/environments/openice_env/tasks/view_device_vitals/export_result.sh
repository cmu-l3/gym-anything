#!/bin/bash
echo "=== Exporting view_device_vitals task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial state
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")

# Get current state
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)

# Check for device/vitals related windows
DEVICE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "device|adapter|monitor|vital|waveform|ecg|spo2|heart|pulse" | wc -l)

# Check OpenICE status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# List all windows
ALL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | head -20)

# Check logs for device and vital signs activity
VITALS_IN_LOG="false"
if grep -iE "vital|waveform|ecg|spo2|heart|numeric|sample" /home/ga/openice/logs/openice.log 2>/dev/null | tail -30 > /dev/null 2>&1; then
    VITALS_IN_LOG="true"
fi

# Check for device adapter activity
DEVICE_ACTIVITY="false"
if grep -iE "device|adapter|monitor|publishing|data" /home/ga/openice/logs/openice.log 2>/dev/null | tail -30 > /dev/null 2>&1; then
    DEVICE_ACTIVITY="true"
fi

# Evidence of viewing device details (additional windows opened)
DETAILS_VIEWED="false"
if [ $CURRENT_WINDOWS -gt $((INITIAL_WINDOWS + 1)) ]; then
    DETAILS_VIEWED="true"
fi

# Create result JSON
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_window_count": $INITIAL_WINDOWS,
    "final_window_count": $CURRENT_WINDOWS,
    "device_related_windows": $DEVICE_WINDOWS,
    "openice_running": $OPENICE_RUNNING,
    "vitals_in_log": $VITALS_IN_LOG,
    "device_activity": $DEVICE_ACTIVITY,
    "details_viewed": $DETAILS_VIEWED,
    "all_windows": "$(echo "$ALL_WINDOWS" | tr '\n' '|' | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Result exported ==="
echo "OpenICE running: $OPENICE_RUNNING"
echo "Device windows: $DEVICE_WINDOWS"
echo "Vitals in log: $VITALS_IN_LOG"
cat /tmp/task_result.json
