#!/bin/bash
echo "=== Exporting fault_tolerance_test result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

OPENICE_RUNNING="false"
is_openice_running && OPENICE_RUNNING="true"

# Count occurrences of multiparameter device creation in new log
# For fault tolerance, we expect at least 3 (initial 2 + 1 replacement)
# Use python for counting to avoid grep -c || echo issue
MULTIPARAMETER_CREATE_COUNT=$(echo "$NEW_LOG" | python3 -c "
import sys, re
log = sys.stdin.read()
count = len(re.findall(r'(?i)(multiparameter|multiParam|multiparammonitor)', log))
print(count)
" 2>/dev/null || echo "0")

# Any device creation at all
ANY_DEVICE_CREATED=0
echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|device.*adapt|ICE.*Device" && ANY_DEVICE_CREATED=1

# Multiple devices (at least 2 instances)
TWO_DEVICES_CREATED=0
[ "$MULTIPARAMETER_CREATE_COUNT" -ge 2 ] 2>/dev/null && TWO_DEVICES_CREATED=1
# Also: if window count went up by 2+ at some point (we can't track intermediate state,
# but if final window count is >= initial + 1 that suggests devices were created)
[ $WINDOW_INCREASE -ge 1 ] && [ "$MULTIPARAMETER_CREATE_COUNT" -ge 2 ] && TWO_DEVICES_CREATED=1

# Device recovery (3+ instances = initial pair + replacement)
DEVICE_RECOVERY=0
[ "$MULTIPARAMETER_CREATE_COUNT" -ge 3 ] 2>/dev/null && DEVICE_RECOVERY=1

# Evidence of device stop/failure (window count at end less than a peak)
# We check if a device-type window appeared AND then count went back near baseline
# Since we can't track the peak, we look for device creation + final count near initial
# A crude proxy: if 2+ devices were created but final window count is less than initial + 2
DEVICE_STOPPED=0
if [ $TWO_DEVICES_CREATED -eq 1 ] && [ $WINDOW_INCREASE -lt 2 ]; then
    DEVICE_STOPPED=1
fi
# Also check if final window count fell back after going up
# (if we created 2 devices = +2 windows, but final is +0 or +1, one was closed)

# Vital Signs app launched
VITAL_SIGNS_LAUNCHED=0
echo "$NEW_LOG" | grep -qiE "VitalSigns|vital.?sign.*app|vital.?sign.*launch|vital.?sign.*open" && VITAL_SIGNS_LAUNCHED=1

# Report file
REPORT_FILE="/home/ga/Desktop/fault_tolerance_report.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_HAS_FAILURE=0
REPORT_HAS_RECOVERY=0
REPORT_HAS_ASSESSMENT=0
REPORT_HAS_TWO_DEVICES=0
REPORT_HAS_VITAL_SIGNS=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    grep -qiE "fail|close|stop|terminat|disconnect|remov" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_FAILURE=1
    grep -qiE "recover|restor|replace|restart|new.*device|creat.*new|redundan" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_RECOVERY=1
    grep -qiE "assess|suitab|recommend|reliable|safe|validat|deploy" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_ASSESSMENT=1
    grep -qiE "two.*monitor|dual.*monitor|second.*monitor|both.*device|redundant|backup" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_TWO_DEVICES=1
    grep -qiE "vital.?sign|vital.*sign" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_VITAL_SIGNS=1
fi

cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_window_count": $INITIAL_WINDOWS,
    "final_window_count": $FINAL_WINDOWS,
    "window_increase": $WINDOW_INCREASE,
    "openice_running": $OPENICE_RUNNING,
    "any_device_created": $ANY_DEVICE_CREATED,
    "two_devices_created": $TWO_DEVICES_CREATED,
    "multiparameter_create_count": $MULTIPARAMETER_CREATE_COUNT,
    "device_stopped": $DEVICE_STOPPED,
    "device_recovery": $DEVICE_RECOVERY,
    "vital_signs_launched": $VITAL_SIGNS_LAUNCHED,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_has_failure": $REPORT_HAS_FAILURE,
    "report_has_recovery": $REPORT_HAS_RECOVERY,
    "report_has_assessment": $REPORT_HAS_ASSESSMENT,
    "report_has_two_devices": $REPORT_HAS_TWO_DEVICES,
    "report_has_vital_signs": $REPORT_HAS_VITAL_SIGNS
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
echo "Devices created: $MULTIPARAMETER_CREATE_COUNT (2-device: $TWO_DEVICES_CREATED, recovery: $DEVICE_RECOVERY)"
echo "Device stopped: $DEVICE_STOPPED | Vital Signs: $VITAL_SIGNS_LAUNCHED"
echo "Report: exists=$REPORT_EXISTS size=$REPORT_SIZE"
cat /tmp/task_result.json
