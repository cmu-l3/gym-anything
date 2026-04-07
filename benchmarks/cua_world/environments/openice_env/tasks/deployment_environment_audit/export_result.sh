#!/bin/bash
echo "=== Exporting deployment_environment_audit task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if OpenICE is running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# ------------------------------------------------------------------
# Device Verification (Log & Window Analysis)
# ------------------------------------------------------------------

# Get new log lines
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check for Multiparameter Monitor
MONITOR_CREATED="false"
# Check logs
if echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|vital.*monitor"; then
    MONITOR_CREATED="true"
fi
# Check active windows
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter|vital.*monitor"; then
    MONITOR_CREATED="true"
fi

# Check for Infusion Pump
PUMP_CREATED="false"
# Check logs
if echo "$NEW_LOG" | grep -qiE "infusion.?pump|pump.*adapter"; then
    PUMP_CREATED="true"
fi
# Check active windows
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "infusion.?pump|pump.*adapter"; then
    PUMP_CREATED="true"
fi

# ------------------------------------------------------------------
# Audit File Verification
# ------------------------------------------------------------------

FILE_PATH="/home/ga/Desktop/deployment_audit.txt"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
HAS_JVM_PROPS="false"
HAS_MONITOR_TEXT="false"
HAS_PUMP_TEXT="false"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    
    # Check content for JVM properties (look for common keys)
    if grep -q "java.vm.name" "$FILE_PATH" || grep -q "java.version" "$FILE_PATH" || grep -q "sun.java.command" "$FILE_PATH"; then
        HAS_JVM_PROPS="true"
    fi
    
    # Check content for device list text
    if grep -qi "multiparameter" "$FILE_PATH"; then
        HAS_MONITOR_TEXT="true"
    fi
    if grep -qi "infusion" "$FILE_PATH" && grep -qi "pump" "$FILE_PATH"; then
        HAS_PUMP_TEXT="true"
    fi
fi

# ------------------------------------------------------------------
# JSON Creation
# ------------------------------------------------------------------

create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "monitor_device_active": $MONITOR_CREATED,
    "pump_device_active": $PUMP_CREATED,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "content_has_jvm_props": $HAS_JVM_PROPS,
    "content_has_monitor_text": $HAS_MONITOR_TEXT,
    "content_has_pump_text": $HAS_PUMP_TEXT,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Result exported ==="
cat /tmp/task_result.json