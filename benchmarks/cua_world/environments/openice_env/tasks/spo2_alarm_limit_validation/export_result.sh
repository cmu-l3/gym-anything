#!/bin/bash
echo "=== Exporting spo2_alarm_limit_validation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (framework requirement)
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Analyze Logs for Activity
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get new log lines
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check for Pulse Oximeter creation
PULSE_OX_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Pulse.?Oximeter|SpO2|SimulatedPulseOximeter"; then
    PULSE_OX_CREATED="true"
fi

# Check for Alarm List app launch
ALARM_APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "AlarmList|IceAlarm|Alarm.*List"; then
    ALARM_APP_LAUNCHED="true"
fi

# 2. Check Window Titles as backup
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
if echo "$CURRENT_WINDOWS" | grep -qiE "Pulse.?Oximeter|SpO2"; then
    PULSE_OX_CREATED="true"
fi
if echo "$CURRENT_WINDOWS" | grep -qiE "Alarm.*List"; then
    ALARM_APP_LAUNCHED="true"
fi

# 3. Check Evidence Screenshot
EVIDENCE_PATH="/home/ga/Desktop/alarm_trigger_evidence.png"
EVIDENCE_EXISTS="false"
EVIDENCE_SIZE=0
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
fi

# 4. Check Report
REPORT_PATH="/home/ga/Desktop/alarm_threshold_report.json"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_VALID_JSON="false"
REPORT_THRESHOLD=-1

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH")
    
    # Simple python check for JSON validity and extracting threshold
    PYTHON_CHECK=$(python3 -c "
import json, sys
try:
    data = json.load(open('$REPORT_PATH'))
    print(json.dumps({'valid': True, 'threshold': data.get('threshold_value', -1)}))
except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e)}))
" 2>/dev/null)
    
    REPORT_VALID_JSON=$(echo "$PYTHON_CHECK" | python3 -c "import sys, json; print(json.load(sys.stdin).get('valid', False))")
    REPORT_THRESHOLD=$(echo "$PYTHON_CHECK" | python3 -c "import sys, json; print(json.load(sys.stdin).get('threshold', -1))")
fi

# Create result JSON
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "pulse_oximeter_created": $PULSE_OX_CREATED,
    "alarm_app_launched": $ALARM_APP_LAUNCHED,
    "evidence_screenshot_exists": $EVIDENCE_EXISTS,
    "evidence_screenshot_size": $EVIDENCE_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_valid_json": $REPORT_VALID_JSON,
    "reported_threshold": $REPORT_THRESHOLD,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "evidence_path": "$EVIDENCE_PATH"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json