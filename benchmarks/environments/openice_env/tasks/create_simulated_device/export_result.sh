#!/bin/bash
echo "=== Exporting create_simulated_device task result ==="

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

# Check for device-related windows
# OpenICE creates separate windows for device adapters
DEVICE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "device|adapter|monitor|simulator|simulated|vital|multiparameter" | wc -l)

# Check for OpenICE process
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# List all windows for debugging
ALL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | head -20)

# Check if OpenICE window title changed (may indicate device added)
OPENICE_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "openice|ice|supervisor|demo" | head -1)

# Check for evidence of device creation in window titles or content
DEVICE_EVIDENCE="false"
if [ $DEVICE_WINDOWS -gt 0 ] || [ $CURRENT_WINDOWS -gt $INITIAL_WINDOWS ]; then
    DEVICE_EVIDENCE="true"
fi

# Check OpenICE log for device creation
DEVICE_IN_LOG="false"
if grep -iE "device|adapter|monitor|started|connected" /home/ga/openice/logs/openice.log 2>/dev/null | tail -20 | grep -iE "simulated|monitor" > /dev/null 2>&1; then
    DEVICE_IN_LOG="true"
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
    "device_evidence_found": $DEVICE_EVIDENCE,
    "device_in_log": $DEVICE_IN_LOG,
    "openice_window_title": "$(echo "$OPENICE_TITLE" | sed 's/"/\\"/g')",
    "all_windows": "$(echo "$ALL_WINDOWS" | tr '\n' '|' | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Result exported ==="
echo "OpenICE running: $OPENICE_RUNNING"
echo "Device evidence: $DEVICE_EVIDENCE"
echo "Window count change: $INITIAL_WINDOWS -> $CURRENT_WINDOWS"
cat /tmp/task_result.json
