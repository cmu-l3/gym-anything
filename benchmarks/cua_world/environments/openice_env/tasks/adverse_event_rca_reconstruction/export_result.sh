#!/bin/bash
echo "=== Exporting Adverse Event RCA Reconstruction result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Window Analysis
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))
CURRENT_WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null)

# 4. Log Analysis (New lines only)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get content added during task
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# 5. Check OpenICE status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# 6. Detect Pulse Oximeter Creation (The Incident Device)
PULSE_OX_CREATED="false"
# Check logs
if echo "$NEW_LOG" | grep -qiE "pulse.?ox|spo2.*sim|oximeter|PulseOximeter"; then
    PULSE_OX_CREATED="true"
fi
# Check window titles
if echo "$CURRENT_WINDOW_LIST" | grep -qiE "pulse.?ox|spo2.*sim|oximeter"; then
    PULSE_OX_CREATED="true"
fi

# 7. Detect Multiparameter Monitor Creation (The Recommended Device)
MULTIPARAM_CREATED="false"
# Check logs
if echo "$NEW_LOG" | grep -qiE "multi.?param|monitor.*sim|philips|multiparameter"; then
    MULTIPARAM_CREATED="true"
fi
# Check window titles
if echo "$CURRENT_WINDOW_LIST" | grep -qiE "multi.?param|monitor.*sim|multiparameter"; then
    MULTIPARAM_CREATED="true"
fi

# 8. Detect Vital Signs App Launch
APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "vital.?sign|vitals|ice.*app"; then
    APP_LAUNCHED="true"
fi
if echo "$CURRENT_WINDOW_LIST" | grep -qiE "vital.?sign|vitals"; then
    APP_LAUNCHED="true"
fi

# 9. Verify RCA Report
REPORT_PATH="/home/ga/Desktop/rca_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT_INCIDENT="false"
REPORT_CONTENT_GAP="false"
REPORT_CONTENT_ROOT="false"
REPORT_CONTENT_ACTION="false"
REPORT_CONTENT_OPENICE="false"
REPORT_STRUCTURE_SCORE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Content checks (case insensitive)
    # Incident: hypotension, blood pressure, bp drop
    if grep -qiE "hypotension|blood pressure|BP|drop" "$REPORT_PATH"; then
        REPORT_CONTENT_INCIDENT="true"
    fi
    
    # Gap: pulse ox, spo2, oximeter
    if grep -qiE "pulse.?ox|spo2|oximeter" "$REPORT_PATH"; then
        REPORT_CONTENT_GAP="true"
    fi
    
    # Root Cause: transport, disconnect, reconnect
    if grep -qiE "transport|disconnect|reconnect|root cause|RCA" "$REPORT_PATH"; then
        REPORT_CONTENT_ROOT="true"
    fi
    
    # Action: checklist, protocol, corrective
    if grep -qiE "checklist|protocol|corrective|recommendation" "$REPORT_PATH"; then
        REPORT_CONTENT_ACTION="true"
    fi
    
    # OpenICE ref
    if grep -qiE "openice|simul|integrat" "$REPORT_PATH"; then
        REPORT_CONTENT_OPENICE="true"
    fi
    
    # Structure check: Count blank lines as proxy for paragraphs
    PARAGRAPHS=$(grep -c "^$" "$REPORT_PATH" || echo "0")
    REPORT_STRUCTURE_SCORE=$PARAGRAPHS
fi

# 10. Create JSON Result
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "pulse_ox_created": $PULSE_OX_CREATED,
    "multiparam_created": $MULTIPARAM_CREATED,
    "app_launched": $APP_LAUNCHED,
    "window_increase": $WINDOW_INCREASE,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_content_incident": $REPORT_CONTENT_INCIDENT,
    "report_content_gap": $REPORT_CONTENT_GAP,
    "report_content_root": $REPORT_CONTENT_ROOT,
    "report_content_action": $REPORT_CONTENT_ACTION,
    "report_content_openice": $REPORT_CONTENT_OPENICE,
    "report_structure_count": $REPORT_STRUCTURE_SCORE,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json