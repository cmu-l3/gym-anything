#!/bin/bash
echo "=== Exporting icu_monitoring_setup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Get only new log lines since task start
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

OPENICE_RUNNING="false"
is_openice_running && OPENICE_RUNNING="true"

# Detect each device type created (binary flags - no grep -c || echo)
MULTIPARAMETER_CREATED=0
echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam" && MULTIPARAMETER_CREATED=1
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter" && MULTIPARAMETER_CREATED=1

CO2_CREATED=0
echo "$NEW_LOG" | grep -qiE "CO2|carbon.?di|etco2|capno|resp.*gas|SimCO2" && CO2_CREATED=1
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "CO2|capno|carbon.?di" && CO2_CREATED=1

# Third device - any device other than multiparameter and CO2
THIRD_DEVICE_CREATED=0
echo "$NEW_LOG" | grep -qiE "infusion|pump|NIBP|blood.*press|ECG|pulse.?ox|SpO2.*adapt|temperature|temp.*adapt|IBP|invasive" && THIRD_DEVICE_CREATED=1
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "infusion|pump|NIBP|ECG|oxim|temp.*adapt|IBP" && THIRD_DEVICE_CREATED=1

# Count how many distinct device types were created
DEVICE_TYPE_COUNT=0
[ $MULTIPARAMETER_CREATED -eq 1 ] && DEVICE_TYPE_COUNT=$((DEVICE_TYPE_COUNT + 1))
[ $CO2_CREATED -eq 1 ] && DEVICE_TYPE_COUNT=$((DEVICE_TYPE_COUNT + 1))
[ $THIRD_DEVICE_CREATED -eq 1 ] && DEVICE_TYPE_COUNT=$((DEVICE_TYPE_COUNT + 1))

# Vital Signs app launched
VITAL_SIGNS_LAUNCHED=0
echo "$NEW_LOG" | grep -qiE "vital.?sign|VitalSign|vital.*app" && VITAL_SIGNS_LAUNCHED=1

# Device detail view opened (window count increased significantly)
DETAILS_VIEWED=0
[ $WINDOW_INCREASE -gt 1 ] && DETAILS_VIEWED=1

# Report file
REPORT_FILE="/home/ga/Desktop/monitoring_checklist.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_HAS_MULTIPARAMETER=0
REPORT_HAS_CO2=0
REPORT_HAS_THIRD=0
REPORT_HAS_CONFIRMATION=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    grep -qiE "multiparameter|multi.?param" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_MULTIPARAMETER=1
    grep -qiE "CO2|carbon.?di|etco2|capno|respiratory" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_CO2=1
    grep -qiE "infusion|pump|NIBP|blood.*press|pulse.?ox|temperature|ECG|SpO2|oxygen|IBP|invasive|ventilat" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_THIRD=1
    grep -qiE "active|flowing|streaming|confirmed|running|connected|operational" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_CONFIRMATION=1
fi

cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_window_count": $INITIAL_WINDOWS,
    "final_window_count": $FINAL_WINDOWS,
    "window_increase": $WINDOW_INCREASE,
    "openice_running": $OPENICE_RUNNING,
    "multiparameter_created": $MULTIPARAMETER_CREATED,
    "co2_created": $CO2_CREATED,
    "third_device_created": $THIRD_DEVICE_CREATED,
    "device_type_count": $DEVICE_TYPE_COUNT,
    "vital_signs_launched": $VITAL_SIGNS_LAUNCHED,
    "details_viewed": $DETAILS_VIEWED,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_has_multiparameter": $REPORT_HAS_MULTIPARAMETER,
    "report_has_co2": $REPORT_HAS_CO2,
    "report_has_third_device": $REPORT_HAS_THIRD,
    "report_has_confirmation": $REPORT_HAS_CONFIRMATION
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
echo "Devices: multiparameter=$MULTIPARAMETER_CREATED co2=$CO2_CREATED third=$THIRD_DEVICE_CREATED (count=$DEVICE_TYPE_COUNT)"
echo "Vital Signs app: $VITAL_SIGNS_LAUNCHED | Window increase: $WINDOW_INCREASE"
echo "Report: exists=$REPORT_EXISTS size=$REPORT_SIZE"
cat /tmp/task_result.json
