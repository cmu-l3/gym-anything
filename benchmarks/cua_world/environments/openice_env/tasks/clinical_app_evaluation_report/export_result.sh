#!/bin/bash
echo "=== Exporting clinical_app_evaluation_report result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Retrieve timestamps and initial states
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")

# Get current window count
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Get NEW log lines only (to avoid false positives from previous runs/startup)
LOG_FILE="/home/ga/openice/logs/openice.log"
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# --- 1. DETECT CREATED DEVICES ---
# Search distinct device types in NEW logs and CURRENT window titles
# Keywords correspond to OpenICE simulated device types
DEVICE_TYPES_DETECTED=0
DETECTED_DEVICES_LIST=""

# Helper to check for a device type
check_device() {
    local name=$1
    local regex=$2
    if echo "$NEW_LOG" | grep -qiE "$regex" || DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "$regex"; then
        DEVICE_TYPES_DETECTED=$((DEVICE_TYPES_DETECTED + 1))
        DETECTED_DEVICES_LIST="$DETECTED_DEVICES_LIST $name"
    fi
}

check_device "Multiparameter" "multiparameter|multiParam|vital.*monitor"
check_device "InfusionPump" "infusion.?pump|pump.*adapter|PumpSim"
check_device "CO2/Capno" "CO2|carbon.?di|etco2|capno"
check_device "PulseOximeter" "pulse.?ox|SpO2.*adapt"
check_device "NIBP" "NIBP|blood.?press"
check_device "Ventilator" "ventilat"
check_device "ECG" "ECG|electro"

# --- 2. DETECT LAUNCHED CLINICAL APPS ---
# Search for app launch events in NEW logs and CURRENT window titles
APPS_LAUNCHED_COUNT=0
DETECTED_APPS_LIST=""

check_app() {
    local name=$1
    local regex=$2
    if echo "$NEW_LOG" | grep -qiE "$regex" || DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "$regex"; then
        APPS_LAUNCHED_COUNT=$((APPS_LAUNCHED_COUNT + 1))
        DETECTED_APPS_LIST="$DETECTED_APPS_LIST $name"
    fi
}

check_app "VitalSigns" "vital.?sign|VitalSign|vital.*app"
check_app "InfusionSafety" "infusion.?safety|InfusionSafety|safety.*app"
check_app "PatientID" "patient.?id|PatientID"
check_app "XrayViewer" "xray|x-ray"
check_app "Alarm" "alarm|alert"

# Fallback: If window count increased significantly but we missed specific names
# Assume some interaction happened if we have > 3 new windows
if [ $WINDOW_INCREASE -ge 3 ] && [ $APPS_LAUNCHED_COUNT -eq 0 ]; then
    WINDOW_INTERACTION_FLAG="true"
else
    WINDOW_INTERACTION_FLAG="false"
fi

# --- 3. ANALYZE REPORT FILE ---
REPORT_FILE="/home/ga/Desktop/clinical_app_evaluation.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_VALID_TIMESTAMP="false"
REPORT_CONTENT_APPS=0
REPORT_CONTENT_CLINICAL=0
REPORT_CONTENT_RECOMMEND=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID_TIMESTAMP="true"
    fi
    
    # Check for app names in report
    if grep -qiE "vital|infusion|patient|xray|x-ray" "$REPORT_FILE"; then
        # Count occurrences of distinct apps mentioned
        CNT=0
        grep -qiE "vital" "$REPORT_FILE" && CNT=$((CNT+1))
        grep -qiE "infusion|safety" "$REPORT_FILE" && CNT=$((CNT+1))
        grep -qiE "patient" "$REPORT_FILE" && CNT=$((CNT+1))
        grep -qiE "xray|x-ray" "$REPORT_FILE" && CNT=$((CNT+1))
        REPORT_CONTENT_APPS=$CNT
    fi
    
    # Check for clinical terms
    if grep -qiE "monitoring|waveform|threshold|interlock|safety|medical|clinical|data" "$REPORT_FILE"; then
        REPORT_CONTENT_CLINICAL="true"
    else
        REPORT_CONTENT_CLINICAL="false"
    fi
    
    # Check for evaluation/recommendation language
    if grep -qiE "recommend|evaluat|compare|comparison|pros|cons|suitable|select|deploy" "$REPORT_FILE"; then
        REPORT_CONTENT_RECOMMEND="true"
    else
        REPORT_CONTENT_RECOMMEND="false"
    fi
fi

# Create result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_windows": $INITIAL_WINDOWS,
    "final_windows": $FINAL_WINDOWS,
    "window_increase": $WINDOW_INCREASE,
    "devices_detected_count": $DEVICE_TYPES_DETECTED,
    "devices_list": "$DETECTED_DEVICES_LIST",
    "apps_launched_count": $APPS_LAUNCHED_COUNT,
    "apps_list": "$DETECTED_APPS_LIST",
    "window_interaction_flag": $WINDOW_INTERACTION_FLAG,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "report_valid_timestamp": $REPORT_VALID_TIMESTAMP,
    "report_distinct_apps_mentioned": $REPORT_CONTENT_APPS,
    "report_has_clinical_terms": $REPORT_CONTENT_CLINICAL,
    "report_has_recommendation": $REPORT_CONTENT_RECOMMEND
}
EOF

echo "=== Export Complete ==="
echo "Devices: $DEVICE_TYPES_DETECTED | Apps: $APPS_LAUNCHED_COUNT"
echo "Report: $REPORT_EXISTS ($REPORT_SIZE bytes)"
cat /tmp/task_result.json