#!/bin/bash
echo "=== Exporting MEWS Device Feasibility Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Collect Time Information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze Output Files
SCREENSHOT_PATH="/home/ga/Desktop/mews_monitoring_screenshot.png"
REPORT_PATH="/home/ga/Desktop/mews_feasibility_assessment.txt"

# Check Screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
if [ -f "$SCREENSHOT_PATH" ]; then
    S_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$S_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    fi
fi

# Check Report
REPORT_EXISTS="false"
REPORT_SIZE="0"
if [ -f "$REPORT_PATH" ]; then
    R_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$R_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    fi
fi

# 4. Analyze OpenICE Activity (Logs & Windows)

# Get new log content
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_SIZE=$(cat /tmp/initial_log_size.txt 2>/dev/null || echo "0")
# Safe tail extraction
NEW_LOG_LINES=$(tail -c +$((INITIAL_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Search logs for specific device types created during task
LOG_MULTIPARAM=$(echo "$NEW_LOG_LINES" | grep -iE "multiparameter|monitor.*simulator" | wc -l)
LOG_PULSEOX=$(echo "$NEW_LOG_LINES" | grep -iE "pulse.*ox|spo2|oximeter" | wc -l)
LOG_TEMP=$(echo "$NEW_LOG_LINES" | grep -iE "temp|therm" | wc -l)
LOG_APP_LAUNCH=$(echo "$NEW_LOG_LINES" | grep -iE "vital.*sign|clinical.*app" | wc -l)

# Analyze Window Titles (Current vs Initial)
touch /tmp/initial_windows.txt
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l)
# Filter for device-looking windows that weren't there before
NEW_WINDOWS_COUNT=$(diff <(cat /tmp/initial_windows.txt) <(echo "$CURRENT_WINDOWS") | grep ">" | wc -l)

# Check specific keywords in current window list
WIN_MULTIPARAM=$(echo "$CURRENT_WINDOWS" | grep -iE "multiparameter" | wc -l)
WIN_PULSEOX=$(echo "$CURRENT_WINDOWS" | grep -iE "pulse.*ox|spo2" | wc -l)
WIN_TEMP=$(echo "$CURRENT_WINDOWS" | grep -iE "temp|therm" | wc -l)
WIN_VITALS_APP=$(echo "$CURRENT_WINDOWS" | grep -iE "vital.*sign" | wc -l)

# 5. Check if OpenICE is still running
APP_RUNNING="false"
if is_openice_running; then
    APP_RUNNING="true"
fi

# 6. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "size_bytes": $SCREENSHOT_SIZE,
        "path": "$SCREENSHOT_PATH"
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "size_bytes": $REPORT_SIZE,
        "path": "$REPORT_PATH"
    },
    "logs": {
        "multiparam_matches": $LOG_MULTIPARAM,
        "pulseox_matches": $LOG_PULSEOX,
        "temp_matches": $LOG_TEMP,
        "app_launch_matches": $LOG_APP_LAUNCH
    },
    "windows": {
        "new_count": $NEW_WINDOWS_COUNT,
        "multiparam_visible": $WIN_MULTIPARAM,
        "pulseox_visible": $WIN_PULSEOX,
        "temp_visible": $WIN_TEMP,
        "vitals_app_visible": $WIN_VITALS_APP
    }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json