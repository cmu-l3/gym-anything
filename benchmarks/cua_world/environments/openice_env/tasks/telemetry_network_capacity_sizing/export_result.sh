#!/bin/bash
echo "=== Exporting telemetry_network_capacity_sizing result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check for Report File
REPORT_PATH="/home/ga/Desktop/capacity_plan.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Copy report to tmp for easier extraction by verifier
    cp "$REPORT_PATH" /tmp/capacity_plan_copy.txt 2>/dev/null || true
    chmod 666 /tmp/capacity_plan_copy.txt 2>/dev/null || true
fi

# 4. Check for Device Creation (Window Analysis)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((CURRENT_WINDOWS - INITIAL_WINDOWS))

# Specific check for Multiparameter Monitor in window titles
MONITOR_WINDOW_DETECTED="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "multiparameter|monitor|device" > /dev/null; then
    # Filter out the main Supervisor window if it contains those words, though usually it's "OpenICE Supervisor"
    # A created device usually spawns a new window or adds to the list
    if [ "$WINDOW_INCREASE" -ge 1 ]; then
        MONITOR_WINDOW_DETECTED="true"
    fi
fi

# 5. Check OpenICE Log for device activity
LOG_FILE="/home/ga/openice/logs/openice.log"
DEVICE_LOG_ACTIVITY="false"
# Look for recent log entries (last 100 lines) related to device creation
if tail -n 100 "$LOG_FILE" 2>/dev/null | grep -iE "DeviceAdapter|Multiparameter|Publishing" > /dev/null; then
    DEVICE_LOG_ACTIVITY="true"
fi

# 6. Create JSON result
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "monitor_window_detected": $MONITOR_WINDOW_DETECTED,
    "window_increase": $WINDOW_INCREASE,
    "device_log_activity": $DEVICE_LOG_ACTIVITY,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export complete ==="
cat /tmp/task_result.json