#!/bin/bash
echo "=== Exporting hypotension_intervention_drill result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (Agent may have taken one, but we take one for verification)
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Window counts (proxy for device creation)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Get ONLY new log lines since task start
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check OpenICE running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# ---------------------------------------------------------
# Device Detection (Logs + Window Titles)
# ---------------------------------------------------------

# 1. Multiparameter Monitor
MONITOR_DETECTED="false"
if echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|vital.*monitor"; then
    MONITOR_DETECTED="true"
fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter|vital.*monitor"; then
    MONITOR_DETECTED="true"
fi

# 2. Infusion Pump
PUMP_DETECTED="false"
if echo "$NEW_LOG" | grep -qiE "infusion.?pump|pump.*adapter|InfusionPump"; then
    PUMP_DETECTED="true"
fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "infusion.?pump|pump.*adapter"; then
    PUMP_DETECTED="true"
fi

# ---------------------------------------------------------
# Report Verification
# ---------------------------------------------------------
REPORT_FILE="/home/ga/Desktop/hypotension_drill_log.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT_BP="false"
REPORT_CONTENT_RATE="false"
REPORT_VALUES_VALID="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")

    # Read content for keywords
    CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    
    # Check for BP mentions (systolic, bp, pressure)
    if echo "$CONTENT" | grep -qE "systolic|bp|pressure|mmhg"; then
        REPORT_CONTENT_BP="true"
    fi

    # Check for Pump/Rate mentions (rate, flow, bolus, ml/hr)
    if echo "$CONTENT" | grep -qE "rate|flow|bolus|ml/hr|pump"; then
        REPORT_CONTENT_RATE="true"
    fi

    # Check for target numeric values (naive check for presence of numbers in range)
    # We look for numbers < 90 and > 500 in the text
    # This is a heuristic; strict parsing is hard in bash
    if echo "$CONTENT" | grep -qE "[0-8][0-9][^0-9]|[0-9]\b" && echo "$CONTENT" | grep -qE "[5-9][0-9][0-9]"; then
        REPORT_VALUES_VALID="true"
    fi
fi

# ---------------------------------------------------------
# Screenshot Evidence
# ---------------------------------------------------------
# Check if agent saved any screenshots as requested
AGENT_SCREENSHOT_EXISTS="false"
# Look for png/jpg in Desktop created after task start
if find /home/ga/Desktop -maxdepth 1 -name "*.*" -newermt "@$TASK_START" | grep -qiE "\.png$|\.jpg$|\.jpeg$"; then
    AGENT_SCREENSHOT_EXISTS="true"
fi

# Create result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "monitor_detected": $MONITOR_DETECTED,
    "pump_detected": $PUMP_DETECTED,
    "window_increase": $WINDOW_INCREASE,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_content_bp": $REPORT_CONTENT_BP,
    "report_content_rate": $REPORT_CONTENT_RATE,
    "report_values_valid": $REPORT_VALUES_VALID,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Result Exported ==="
cat /tmp/task_result.json