#!/bin/bash
echo "=== Exporting Sepsis Simulation Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture system state at end of task
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 2. Check for required user-created files
EVIDENCE_IMG="/home/ga/Desktop/sepsis_vitals_evidence.png"
CONFIG_JSON="/home/ga/Desktop/sepsis_config.json"

IMG_EXISTS="false"
IMG_MTIME=0
if [ -f "$EVIDENCE_IMG" ]; then
    IMG_EXISTS="true"
    IMG_MTIME=$(stat -c %Y "$EVIDENCE_IMG")
fi

JSON_EXISTS="false"
JSON_MTIME=0
if [ -f "$CONFIG_JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$CONFIG_JSON")
fi

# 3. Analyze OpenICE Logs for Device Creation & App Launch
# We only look at logs appended AFTER task start
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOGS=$(tail -c +$((INITIAL_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check for Multiparameter Monitor
MONITOR_CREATED="false"
if echo "$NEW_LOGS" | grep -qiE "Multiparameter|MultiParam|Vital.*Monitor"; then
    MONITOR_CREATED="true"
fi

# Check for Infusion Pump
PUMP_CREATED="false"
if echo "$NEW_LOGS" | grep -qiE "Infusion.*Pump|Pump.*Adapter"; then
    PUMP_CREATED="true"
fi

# Check for Vital Signs App
APP_LAUNCHED="false"
if echo "$NEW_LOGS" | grep -qiE "Vital.*Signs|VitalSign|Clinical.*App"; then
    APP_LAUNCHED="true"
fi

# Check window titles as backup for app launch
if DISPLAY=:1 wmctrl -l | grep -qiE "Vital.*Signs"; then
    APP_LAUNCHED="true"
fi

# 4. Take framework verification screenshot
take_screenshot /tmp/task_final_state.png

# 5. Construct Result JSON
# We include specific booleans and paths for the verifier to check
cat > /tmp/task_result_temp.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_screenshot_exists": $IMG_EXISTS,
    "evidence_screenshot_mtime": $IMG_MTIME,
    "config_json_exists": $JSON_EXISTS,
    "config_json_mtime": $JSON_MTIME,
    "log_monitor_created": $MONITOR_CREATED,
    "log_pump_created": $PUMP_CREATED,
    "log_app_launched": $APP_LAUNCHED,
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move safely
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"