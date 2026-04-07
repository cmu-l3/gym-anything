#!/bin/bash
echo "=== Exporting EHR Integration Feasibility Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

# --- DATA COLLECTION ---

# 1. Timestamps
TASK_START=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Log Analysis (Scan only NEW lines)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size.txt 2>/dev/null || echo "0")
# Get new content safely
NEW_LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    CURRENT_SIZE=$(stat -c %s "$LOG_FILE")
    if [ "$CURRENT_SIZE" -gt "$INITIAL_LOG_SIZE" ]; then
        NEW_LOG_CONTENT=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE")
    fi
fi

# Detect Device Creation in Logs (Keywords)
# We count unique device types mentioned in "created" or "started" contexts if possible,
# or just existence of specific device keywords in the new log.
LOG_DEVICES_DETECTED=""
if echo "$NEW_LOG_CONTENT" | grep -qiE "Multiparameter|Multi-Parameter"; then LOG_DEVICES_DETECTED="${LOG_DEVICES_DETECTED}Multiparameter,"; fi
if echo "$NEW_LOG_CONTENT" | grep -qiE "Pulse Oximeter|PulseOx"; then LOG_DEVICES_DETECTED="${LOG_DEVICES_DETECTED}PulseOximeter,"; fi
if echo "$NEW_LOG_CONTENT" | grep -qiE "Infusion Pump|InfusionPump"; then LOG_DEVICES_DETECTED="${LOG_DEVICES_DETECTED}InfusionPump,"; fi
if echo "$NEW_LOG_CONTENT" | grep -qiE "Capnograph|CO2"; then LOG_DEVICES_DETECTED="${LOG_DEVICES_DETECTED}Capnograph,"; fi
if echo "$NEW_LOG_CONTENT" | grep -qiE "Electrocardiogram|ECG"; then LOG_DEVICES_DETECTED="${LOG_DEVICES_DETECTED}ECG,"; fi

# Detect App Launch in Logs
APP_LAUNCHED_LOG="false"
if echo "$NEW_LOG_CONTENT" | grep -qiE "Vital Signs|VitalSigns|ClinicalApp"; then
    APP_LAUNCHED_LOG="true"
fi

# 3. Window Analysis
INITIAL_WINDOWS=$(cat /tmp/initial_windows.txt 2>/dev/null || echo "")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)

# Detect Device Windows (OpenICE spawns windows for devices)
WINDOW_DEVICES_DETECTED=""
if echo "$FINAL_WINDOWS" | grep -qiE "Multiparameter"; then WINDOW_DEVICES_DETECTED="${WINDOW_DEVICES_DETECTED}Multiparameter,"; fi
if echo "$FINAL_WINDOWS" | grep -qiE "Pulse Oximeter"; then WINDOW_DEVICES_DETECTED="${WINDOW_DEVICES_DETECTED}PulseOximeter,"; fi
if echo "$FINAL_WINDOWS" | grep -qiE "Infusion Pump"; then WINDOW_DEVICES_DETECTED="${WINDOW_DEVICES_DETECTED}InfusionPump,"; fi
if echo "$FINAL_WINDOWS" | grep -qiE "Capnograph"; then WINDOW_DEVICES_DETECTED="${WINDOW_DEVICES_DETECTED}Capnograph,"; fi

# Detect App Window
APP_WINDOW_DETECTED="false"
if echo "$FINAL_WINDOWS" | grep -qiE "Vital Signs|VitalSigns"; then
    APP_WINDOW_DETECTED="true"
fi

# 4. Report File Verification
REPORT_PATH="/home/ga/Desktop/ehr_integration_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 5. OpenICE Status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# --- JSON CREATION ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "log_devices_detected": "$LOG_DEVICES_DETECTED",
    "window_devices_detected": "$WINDOW_DEVICES_DETECTED",
    "app_launched_log": $APP_LAUNCHED_LOG,
    "app_window_detected": $APP_WINDOW_DETECTED,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_path": "$REPORT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json