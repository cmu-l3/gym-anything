#!/bin/bash
echo "=== Exporting alarm_audit result ==="

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

# Device creation detection
ANY_DEVICE_CREATED=0
echo "$NEW_LOG" | grep -qiE "device.*adapt|adapt.*start|ICE.*Device|adapter.*created|simul.*device" && ANY_DEVICE_CREATED=1
[ $WINDOW_INCREASE -gt 0 ] && ANY_DEVICE_CREATED=1

MONITOR_DEVICE_CREATED=0
echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|vital.*monitor|monitor.*simul" && MONITOR_DEVICE_CREATED=1
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter" && MONITOR_DEVICE_CREATED=1

# Clinical app launch detection
ANY_APP_LAUNCHED=0
echo "$NEW_LOG" | grep -qiE "vital.?sign|VitalSign|infusion.?safety|InfusionSafety|xray|XrayViewer|patient.?id|PatientId|alarm.*app|clinical.*app" && ANY_APP_LAUNCHED=1

ALARM_APP_LAUNCHED=0
echo "$NEW_LOG" | grep -qiE "alarm.*app|alarm.*display|AlarmDisplay|alarm.*clinical" && ALARM_APP_LAUNCHED=1

# Report file analysis
REPORT_FILE="/home/ga/Desktop/alarm_audit.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_HAS_PARAMS=0
REPORT_HAS_ALARM_TERMS=0
REPORT_HAS_NUMERIC=0
REPORT_HAS_RECOMMENDATIONS=0
REPORT_HAS_HR=0
REPORT_HAS_SPO2=0
REPORT_HAS_RR=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")

    # Specific vital sign parameters
    grep -qiE "heart.?rate|HR[^A-Z]|bpm|beats.*min" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_HR=1
    grep -qiE "SpO2|spo2|oxygen.*satur|pulse.*ox|O2.*sat" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_SPO2=1
    grep -qiE "resp.*rate|respiratory|RR[^A-Z]|breath.*min|tidal|ventilat" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_RR=1
    REPORT_HAS_PARAMS=$((REPORT_HAS_HR + REPORT_HAS_SPO2 + REPORT_HAS_RR))

    # Alarm terminology
    grep -qiE "alarm|threshold|alert|limit|trigger|false.?alarm|fatigue" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_ALARM_TERMS=1

    # Numeric values (thresholds)
    grep -qE "[0-9][0-9]" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_NUMERIC=1

    # Recommendations
    grep -qiE "recommend|suggest|should.*set|adjust.*to|change.*to|propose" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_RECOMMENDATIONS=1
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
    "monitor_device_created": $MONITOR_DEVICE_CREATED,
    "any_app_launched": $ANY_APP_LAUNCHED,
    "alarm_app_launched": $ALARM_APP_LAUNCHED,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_has_hr": $REPORT_HAS_HR,
    "report_has_spo2": $REPORT_HAS_SPO2,
    "report_has_rr": $REPORT_HAS_RR,
    "report_has_params": $REPORT_HAS_PARAMS,
    "report_has_alarm_terms": $REPORT_HAS_ALARM_TERMS,
    "report_has_numeric": $REPORT_HAS_NUMERIC,
    "report_has_recommendations": $REPORT_HAS_RECOMMENDATIONS
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
echo "Device: $ANY_DEVICE_CREATED | App: $ANY_APP_LAUNCHED | Report: $REPORT_EXISTS (${REPORT_SIZE}B)"
echo "Params found: HR=$REPORT_HAS_HR SpO2=$REPORT_HAS_SPO2 RR=$REPORT_HAS_RR"
cat /tmp/task_result.json
