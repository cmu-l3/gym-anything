#!/bin/bash
echo "=== Exporting safety_interlock_fail_safe_validation result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final_screenshot.png

# --- DATA COLLECTION ---

# 1. Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Window Analysis (The core of the "disconnect" verification)
# We need to see what is currently running
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)

# Check for Pulse Oximeter window (Should be GONE in final state)
PULSE_OX_WINDOW_OPEN="false"
if echo "$CURRENT_WINDOWS" | grep -qiE "Pulse.*Ox|SpO2"; then
    PULSE_OX_WINDOW_OPEN="true"
fi

# Check for Infusion Pump window (Should be OPEN)
PUMP_WINDOW_OPEN="false"
if echo "$CURRENT_WINDOWS" | grep -qiE "Infusion.*Pump|Pump"; then
    PUMP_WINDOW_OPEN="true"
fi

# Check for Safety App window (Should be OPEN)
SAFETY_APP_OPEN="false"
if echo "$CURRENT_WINDOWS" | grep -qiE "Infusion.*Safety|Safety"; then
    SAFETY_APP_OPEN="true"
fi

# 3. Log Analysis (To verify creation history)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Did we create a Pulse Oximeter?
LOG_PULSE_OX_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Pulse.*Ox|SpO2.*Monitor"; then
    LOG_PULSE_OX_CREATED="true"
fi

# Did we create an Infusion Pump?
LOG_PUMP_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Infusion.*Pump"; then
    LOG_PUMP_CREATED="true"
fi

# Did we launch the Safety App?
LOG_SAFETY_APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "Infusion.*Safety"; then
    LOG_SAFETY_APP_LAUNCHED="true"
fi

# 4. Artifact Verification
BASELINE_SCREENSHOT_EXISTS="false"
if [ -f "/home/ga/Desktop/test_01_baseline.png" ]; then
    BASELINE_SCREENSHOT_EXISTS="true"
fi

FAILSAFE_SCREENSHOT_EXISTS="false"
if [ -f "/home/ga/Desktop/test_02_failsafe.png" ]; then
    FAILSAFE_SCREENSHOT_EXISTS="true"
fi

REPORT_FILE="/home/ga/Desktop/failsafe_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT_VALID="false"
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check for keywords in report
    CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    if [[ "$CONTENT" == *"disconnect"* || "$CONTENT" == *"close"* || "$CONTENT" == *"lost"* ]] && \
       [[ "$CONTENT" == *"pass"* || "$CONTENT" == *"safe"* || "$CONTENT" == *"stop"* ]]; then
        REPORT_CONTENT_VALID="true"
    fi
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "current_windows_list": "$(echo "$CURRENT_WINDOWS" | tr '\n' '|' | sed 's/"/\\"/g')",
    "state": {
        "pulse_ox_window_open": $PULSE_OX_WINDOW_OPEN,
        "pump_window_open": $PUMP_WINDOW_OPEN,
        "safety_app_open": $SAFETY_APP_OPEN
    },
    "history": {
        "log_pulse_ox_created": $LOG_PULSE_OX_CREATED,
        "log_pump_created": $LOG_PUMP_CREATED,
        "log_safety_app_launched": $LOG_SAFETY_APP_LAUNCHED
    },
    "artifacts": {
        "baseline_screenshot_exists": $BASELINE_SCREENSHOT_EXISTS,
        "failsafe_screenshot_exists": $FAILSAFE_SCREENSHOT_EXISTS,
        "report_exists": $REPORT_EXISTS,
        "report_content_valid": $REPORT_CONTENT_VALID,
        "report_size": $REPORT_SIZE
    }
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json