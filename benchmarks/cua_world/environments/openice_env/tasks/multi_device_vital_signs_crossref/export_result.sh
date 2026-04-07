#!/bin/bash
echo "=== Exporting multi_device_vital_signs_crossref result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 1. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Analyze Log Files (New entries only)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get content appended during task
NEW_LOG_CONTENT=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null)

# 3. Detect Created Devices (Log + Window Titles)
# We need 3 specific types: Pulse Ox, MultiParam, and a 3rd distinct one.

# Pulse Oximeter Detection
PULSE_OX_CREATED="false"
if echo "$NEW_LOG_CONTENT" | grep -qiE "PulseOx|Pulse Oximeter|SpO2.*Adapter"; then
    PULSE_OX_CREATED="true"
elif DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Pulse.?Ox"; then
    PULSE_OX_CREATED="true"
fi

# Multiparameter Monitor Detection
MULTIPARAM_CREATED="false"
if echo "$NEW_LOG_CONTENT" | grep -qiE "Multiparameter|Multi-Parameter|IntelliVue"; then
    MULTIPARAM_CREATED="true"
elif DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Multiparameter|Multi-Param"; then
    MULTIPARAM_CREATED="true"
fi

# Third Device Detection
# We look for keywords of OTHER devices, or simply count distinct device creation events
# Common other devices: Infusion Pump, NIBP, ElectroCardioGram, Capnography, etc.
THIRD_DEVICE_CREATED="false"
OTHER_DEVICE_REGEX="Infusion|Pump|NIBP|Blood.*Pressure|ECG|Electro|Capno|CO2|Temperature|Scale"

if echo "$NEW_LOG_CONTENT" | grep -qiE "$OTHER_DEVICE_REGEX"; then
    THIRD_DEVICE_CREATED="true"
elif DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "$OTHER_DEVICE_REGEX"; then
    THIRD_DEVICE_CREATED="true"
fi

# Fallback: If we can't identify the 3rd type specifically, check if window count increased by >= 3
# (assuming 3 devices = 3 windows)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

if [ "$THIRD_DEVICE_CREATED" = "false" ] && [ "$WINDOW_INCREASE" -ge 3 ]; then
    # Loose check: if we have 3 new windows and the other two devices are confirmed, assume 3rd is valid
    THIRD_DEVICE_CREATED="true"
fi

# 4. Detect Vital Signs App Launch
APP_LAUNCHED="false"
if echo "$NEW_LOG_CONTENT" | grep -qiE "Vital.?Sign|Vital.*App|Cardiorespiratory"; then
    APP_LAUNCHED="true"
elif DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Vital.?Sign"; then
    APP_LAUNCHED="true"
fi

# 5. Detect Detail Views Opened
# Detail views create new windows. We expect:
# - Main Supervisor Window (already open)
# - Device 1 Adapter Window
# - Device 2 Adapter Window
# - Device 3 Adapter Window
# - Vital Signs App Window
# - Detail View 1
# - Detail View 2
# Total increase should be at least 4-5 windows if everything is open.
# The task asks for "at least 2 detail views".
DETAIL_VIEWS_OPENED="false"
# If window increase is significant (>3), likely detail views were opened
if [ "$WINDOW_INCREASE" -ge 4 ]; then
    DETAIL_VIEWS_OPENED="true"
fi

# 6. Analyze Report Content
REPORT_PATH="/home/ga/Desktop/device_crossref_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
REPORT_CONTENT_VALID="false"
REPORT_HAS_HEADER="false"
REPORT_HAS_PASS_FAIL="false"
REPORT_HAS_OVERLAP="false"
REPORT_DEVICE_COUNT=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")

    # Read report for analysis
    REPORT_TEXT=$(cat "$REPORT_PATH")
    
    # Check Header (Date, Tech, Facility)
    if echo "$REPORT_TEXT" | grep -qiE "Date|202[0-9]|Technician|QA|Facility|Regional|Hospital"; then
        REPORT_HAS_HEADER="true"
    fi

    # Check PASS/FAIL
    if echo "$REPORT_TEXT" | grep -qE "PASS|FAIL"; then
        REPORT_HAS_PASS_FAIL="true"
    fi

    # Check Overlap/Parameters
    if echo "$REPORT_TEXT" | grep -qiE "Heart.*Rate|SpO2|Blood.*Pressure|BP|Pulse|Saturation"; then
        REPORT_HAS_OVERLAP="true"
    fi

    # Count device mentions in report
    if echo "$REPORT_TEXT" | grep -qiE "Pulse.?Ox"; then ((REPORT_DEVICE_COUNT++)); fi
    if echo "$REPORT_TEXT" | grep -qiE "Multiparameter|Multi-Param"; then ((REPORT_DEVICE_COUNT++)); fi
    if echo "$REPORT_TEXT" | grep -qiE "Infusion|Pump|NIBP|ECG|Capno|CO2|Third"; then ((REPORT_DEVICE_COUNT++)); fi
fi

# 7. Check if OpenICE is still running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "pulse_ox_created": $PULSE_OX_CREATED,
    "multiparam_created": $MULTIPARAM_CREATED,
    "third_device_created": $THIRD_DEVICE_CREATED,
    "app_launched": $APP_LAUNCHED,
    "detail_views_opened": $DETAIL_VIEWS_OPENED,
    "window_increase": $WINDOW_INCREASE,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_has_header": $REPORT_HAS_HEADER,
    "report_has_pass_fail": $REPORT_HAS_PASS_FAIL,
    "report_has_overlap": $REPORT_HAS_OVERLAP,
    "report_device_count": $REPORT_DEVICE_COUNT
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json