#!/bin/bash
echo "=== Exporting sedation_monitoring_protocol result ==="

source /workspace/scripts/task_utils.sh

# 1. Evidence Capture
take_screenshot /tmp/task_final_screenshot.png

# 2. Timing Data
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Window Analysis
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# 4. Log Analysis (New lines only)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get content appended after setup
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# 5. Device Detection (Log & Window Title patterns)
# Multiparameter Monitor
MULTIPARAM_CREATED=0
if echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|vital.*monitor"; then MULTIPARAM_CREATED=1; fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter"; then MULTIPARAM_CREATED=1; fi

# Capnography/CO2
CAPNO_CREATED=0
if echo "$NEW_LOG" | grep -qiE "CO2|carbon.?di|etco2|capno"; then CAPNO_CREATED=1; fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "CO2|capno|carbon"; then CAPNO_CREATED=1; fi

# Pulse Oximeter
PULSEOX_CREATED=0
if echo "$NEW_LOG" | grep -qiE "pulse.?ox|SpO2.*adapt"; then PULSEOX_CREATED=1; fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "pulse.?ox|SpO2"; then PULSEOX_CREATED=1; fi

# Vital Signs App
APP_LAUNCHED=0
if echo "$NEW_LOG" | grep -qiE "vital.?sign|VitalSign|vital.*app"; then APP_LAUNCHED=1; fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "vital.?sign"; then APP_LAUNCHED=1; fi

# 6. Protocol File Analysis
REPORT_FILE="/home/ga/Desktop/sedation_monitoring_protocol.txt"
FILE_EXISTS=0
FILE_SIZE=0
FILE_MTIME=0
HAS_REQ_SECTION=0
HAS_CONFIG_SECTION=0
HAS_CHECKLIST_SECTION=0
HAS_ALARM_SECTION=0
HAS_EMERGENCY_SECTION=0
HAS_ASA_REF=0

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS=1
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Read file content for analysis
    # Use -i for case insensitive
    grep -qiE "monitoring.*requirement|oxygenation|ventilation" "$REPORT_FILE" && HAS_REQ_SECTION=1
    grep -qiE "device.*config|multiparameter|capno|pulse" "$REPORT_FILE" && HAS_CONFIG_SECTION=1
    grep -qiE "checklist|pre-procedure|verify|confirm" "$REPORT_FILE" && HAS_CHECKLIST_SECTION=1
    grep -qiE "alarm|threshold|limit|90|50|mmHg" "$REPORT_FILE" && HAS_ALARM_SECTION=1
    grep -qiE "emergency|response|desaturation|apnea" "$REPORT_FILE" && HAS_EMERGENCY_SECTION=1
    grep -qiE "ASA|American Society|guideline" "$REPORT_FILE" && HAS_ASA_REF=1
fi

# 7. Construct JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "window_increase": $WINDOW_INCREASE,
    "multiparam_created": $MULTIPARAM_CREATED,
    "capno_created": $CAPNO_CREATED,
    "pulseox_created": $PULSEOX_CREATED,
    "app_launched": $APP_LAUNCHED,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "has_req_section": $HAS_REQ_SECTION,
    "has_config_section": $HAS_CONFIG_SECTION,
    "has_checklist_section": $HAS_CHECKLIST_SECTION,
    "has_alarm_section": $HAS_ALARM_SECTION,
    "has_emergency_section": $HAS_EMERGENCY_SECTION,
    "has_asa_ref": $HAS_ASA_REF
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json