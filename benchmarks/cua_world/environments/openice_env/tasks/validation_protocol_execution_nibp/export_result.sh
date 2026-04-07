#!/bin/bash
echo "=== Exporting Validation Protocol: NIBP Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (for visual proof of state)
take_screenshot /tmp/task_final_screenshot.png

# 1. TIMING ANALYSIS
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. LOG ANALYSIS (Check for specific actions performed during task)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get only new log lines
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Detect NIBP Device Creation
DEVICE_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "NIBP|Noninvasive|Multiparameter"; then
    DEVICE_CREATED="true"
fi

# Detect Vital Signs App Launch
APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "VitalSign|vital.*app|demo.*app"; then
    APP_LAUNCHED="true"
fi

# 3. EVIDENCE FILE VERIFICATION
EVIDENCE_SCREENSHOT="/home/ga/Desktop/nibp_reading_captured.png"
EVIDENCE_TEXT="/home/ga/Desktop/nibp_values.txt"

SCREENSHOT_EXISTS="false"
SCREENSHOT_TIMESTAMP="0"
if [ -f "$EVIDENCE_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_TIMESTAMP=$(stat -c %Y "$EVIDENCE_SCREENSHOT")
fi

TEXT_FILE_EXISTS="false"
TEXT_FILE_CONTENT=""
TEXT_TIMESTAMP="0"
if [ -f "$EVIDENCE_TEXT" ]; then
    TEXT_FILE_EXISTS="true"
    TEXT_FILE_CONTENT=$(cat "$EVIDENCE_TEXT")
    TEXT_TIMESTAMP=$(stat -c %Y "$EVIDENCE_TEXT")
fi

# 4. SHUTDOWN VERIFICATION
# Check if "Vital Signs" window is currently open (it should NOT be)
VITALS_WINDOW_OPEN="false"
if DISPLAY=:1 wmctrl -l | grep -i "Vital"; then
    VITALS_WINDOW_OPEN="true"
fi

# Check if it was EVER open (by comparing window lists or logs)
# We assume if APP_LAUNCHED is true, it was open.

# 5. DATA EXTRACTION
# Create a safe JSON export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "device_created_log": $DEVICE_CREATED,
    "app_launched_log": $APP_LAUNCHED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_timestamp": $SCREENSHOT_TIMESTAMP,
    "text_file_exists": $TEXT_FILE_EXISTS,
    "text_file_content": "$(escape_json_value "$TEXT_FILE_CONTENT")",
    "text_timestamp": $TEXT_TIMESTAMP,
    "vitals_window_still_open": $VITALS_WINDOW_OPEN,
    "screenshot_path": "/home/ga/Desktop/nibp_reading_captured.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json