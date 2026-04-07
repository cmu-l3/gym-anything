#!/bin/bash
echo "=== Exporting alarm_fatigue_risk_assessment result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM/manual verification
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ------------------------------------------------------------------
# 1. ANALYZE LOGS (Only new entries)
# ------------------------------------------------------------------
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get only the lines appended during the task
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# ------------------------------------------------------------------
# 2. ANALYZE WINDOWS
# ------------------------------------------------------------------
INITIAL_WINDOW_COUNT=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
CURRENT_WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
FINAL_WINDOW_COUNT=$(echo "$CURRENT_WINDOWS_LIST" | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOW_COUNT - INITIAL_WINDOW_COUNT))

# ------------------------------------------------------------------
# 3. DETECT DEVICES (Log + Window Titles)
# ------------------------------------------------------------------
# Helper function to check regex in log or windows
check_presence() {
    local regex="$1"
    if echo "$NEW_LOG" | grep -qiE "$regex"; then echo "true"; return; fi
    if echo "$CURRENT_WINDOWS_LIST" | grep -qiE "$regex"; then echo "true"; return; fi
    echo "false"
}

# Device 1: Pulse Oximeter
HAS_PULSE_OX=$(check_presence "pulse.?ox|spo2|oximeter")

# Device 2: Multiparameter Monitor
HAS_MULTIPARAM=$(check_presence "multiparameter|multi.?param|philips|monitor")

# Device 3: Infusion Pump
HAS_PUMP=$(check_presence "infusion|pump|syringe")

# Device 4: Capno/NIBP/Other (Generic check for a 4th device type or specific keywords)
HAS_FOURTH_DEVICE="false"
if echo "$NEW_LOG" "$CURRENT_WINDOWS_LIST" | grep -qiE "capno|co2|nibp|blood.?press|temperature|ibp|respiratory"; then
    HAS_FOURTH_DEVICE="true"
fi
# Fallback: if we haven't identified the 4th by name, check if window count increased by >= 6 
# (4 devices + 2 apps = ~6 new windows, usually 1 window per device)
if [ "$HAS_FOURTH_DEVICE" = "false" ] && [ $WINDOW_INCREASE -ge 4 ]; then
    HAS_FOURTH_DEVICE="true"
fi

# Count distinct identified devices
DEVICE_COUNT=0
[ "$HAS_PULSE_OX" = "true" ] && DEVICE_COUNT=$((DEVICE_COUNT + 1))
[ "$HAS_MULTIPARAM" = "true" ] && DEVICE_COUNT=$((DEVICE_COUNT + 1))
[ "$HAS_PUMP" = "true" ] && DEVICE_COUNT=$((DEVICE_COUNT + 1))
[ "$HAS_FOURTH_DEVICE" = "true" ] && DEVICE_COUNT=$((DEVICE_COUNT + 1))

# ------------------------------------------------------------------
# 4. DETECT APPS (Log + Window Titles)
# ------------------------------------------------------------------
HAS_VITAL_SIGNS_APP=$(check_presence "vital.?sign|VitalSign")
HAS_INFUSION_SAFETY_APP=$(check_presence "infusion.?safety|InfusionSafety")

# ------------------------------------------------------------------
# 5. CHECK FILES (Screenshots & Report)
# ------------------------------------------------------------------
check_file() {
    local f="$1"
    local min_size="$2"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$f" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ] && [ "$size" -ge "$min_size" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

SCREENSHOT_VITALS_VALID=$(check_file "/home/ga/Desktop/screenshot_vital_signs.png" 10000)
SCREENSHOT_SAFETY_VALID=$(check_file "/home/ga/Desktop/screenshot_infusion_safety.png" 10000)
REPORT_FILE_VALID=$(check_file "/home/ga/Desktop/alarm_fatigue_assessment.txt" 300)

# ------------------------------------------------------------------
# 6. ANALYZE REPORT CONTENT
# ------------------------------------------------------------------
REPORT_CONTENT_SCORE=0
REPORT_PATH="/home/ga/Desktop/alarm_fatigue_assessment.txt"
if [ "$REPORT_FILE_VALID" = "true" ]; then
    # Check for inventory (device mentions)
    grep -qiE "pulse|oximeter|multiparameter|pump" "$REPORT_PATH" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
    
    # Check for assessment/app mentions
    grep -qiE "vital|sign|safety|interface|display" "$REPORT_PATH" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
    
    # Check for alarm/risk terminology
    grep -qiE "alarm|fatigue|risk|false|threshold|alert|priorit" "$REPORT_PATH" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
    
    # Check for recommendations
    grep -qiE "recommend|suggest|should|improv" "$REPORT_PATH" && REPORT_CONTENT_SCORE=$((REPORT_CONTENT_SCORE + 1))
fi

# ------------------------------------------------------------------
# 7. EXPORT JSON
# ------------------------------------------------------------------
OPENICE_RUNNING="false"
is_openice_running && OPENICE_RUNNING="true"

cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "has_pulse_ox": $HAS_PULSE_OX,
    "has_multiparam": $HAS_MULTIPARAM,
    "has_pump": $HAS_PUMP,
    "has_fourth_device": $HAS_FOURTH_DEVICE,
    "device_count": $DEVICE_COUNT,
    "has_vital_signs_app": $HAS_VITAL_SIGNS_APP,
    "has_infusion_safety_app": $HAS_INFUSION_SAFETY_APP,
    "screenshot_vitals_valid": $SCREENSHOT_VITALS_VALID,
    "screenshot_safety_valid": $SCREENSHOT_SAFETY_VALID,
    "report_valid": $REPORT_FILE_VALID,
    "report_content_score": $REPORT_CONTENT_SCORE,
    "window_increase": $WINDOW_INCREASE
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json