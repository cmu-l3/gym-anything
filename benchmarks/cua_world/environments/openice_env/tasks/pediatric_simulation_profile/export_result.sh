#!/bin/bash
echo "=== Exporting pediatric_simulation_profile result ==="

source /workspace/scripts/task_utils.sh

# Take final framework screenshot (system level)
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# --- 1. FILE VERIFICATION ---
REPORT_PATH="/home/ga/Desktop/pediatric_config.txt"
EVIDENCE_PATH="/home/ga/Desktop/pediatric_evidence.png"

# Check Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # limit size
    fi
fi

# Check Evidence Screenshot (Agent created)
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_EXISTS="true"
    fi
fi

# --- 2. LOG & WINDOW ANALYSIS ---
# Get new log lines
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Detect Monitor Creation
MONITOR_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Multiparameter.*Monitor|Simulated.*Monitor"; then
    MONITOR_CREATED="true"
fi
# Also check window titles
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Multiparameter.*Monitor"; then
    MONITOR_CREATED="true"
fi

# Detect Pump Creation
PUMP_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Infusion.*Pump"; then
    PUMP_CREATED="true"
fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Infusion.*Pump"; then
    PUMP_CREATED="true"
fi

# Detect Vital Signs App
APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "Vital.*Signs"; then
    APP_LAUNCHED="true"
fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Vital.*Signs"; then
    APP_LAUNCHED="true"
fi

# --- 3. EXPORT JSON ---
# Create result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "monitor_created": $MONITOR_CREATED,
    "pump_created": $PUMP_CREATED,
    "app_launched": $APP_LAUNCHED,
    "report_exists": $REPORT_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "evidence_exists": $EVIDENCE_EXISTS,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json