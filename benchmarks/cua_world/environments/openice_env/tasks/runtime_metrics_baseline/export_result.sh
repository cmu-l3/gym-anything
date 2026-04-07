#!/bin/bash
echo "=== Exporting runtime_metrics_baseline result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Timestamps and Initial State
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size.txt 2>/dev/null || echo "0")
INITIAL_WINDOW_COUNT=$(cat /tmp/initial_window_count.txt 2>/dev/null || echo "0")

# 3. Analyze Report File
REPORT_PATH="/home/ga/Desktop/performance_baseline.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
REPORT_CONTENT=""
REPORT_FRESH="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi

    # Read content safely for JSON embedding (limit to 2KB)
    # Python is safest for JSON escaping
    REPORT_CONTENT=$(python3 -c "import json, sys; print(json.dumps(sys.stdin.read(2048)))" < "$REPORT_PATH")
else
    REPORT_CONTENT="\"\""
fi

# 4. Analyze OpenICE Logs (New lines only)
LOG_FILE="/home/ga/openice/logs/openice.log"
NEW_LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    # Get only new lines
    NEW_LOG_CONTENT=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null | tr '\n' ' ' | tr -cd '[:print:]')
fi

# 5. Analyze Windows
CURRENT_WINDOW_COUNT=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//g')

# 6. Check for Device Creation Evidence
# We look for keywords in new logs OR window titles
DEVICE_EVIDENCE_LOG=$(echo "$NEW_LOG_CONTENT" | grep -iE "device|adapter|monitor|simulated|created|started|publishing" | wc -l)
DEVICE_EVIDENCE_WINDOWS=$(echo "$WINDOW_LIST" | grep -iE "device|adapter|monitor|vital|waveform|spo2|ecg|pump|co2" | wc -l)

# 7. Check if OpenICE is still running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# 8. Create JSON Result
# Using a temp file and python to construct JSON ensures validity
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_fresh": $REPORT_FRESH,
    "report_content": $REPORT_CONTENT,
    "initial_window_count": $INITIAL_WINDOW_COUNT,
    "current_window_count": $CURRENT_WINDOW_COUNT,
    "window_list": "$(echo "$WINDOW_LIST" | tr '\n' '|' | sed 's/"/\\"/g')",
    "new_log_content_sample": "$(echo "$NEW_LOG_CONTENT" | cut -c1-1000 | sed 's/"/\\"/g')",
    "device_evidence_log_count": $DEVICE_EVIDENCE_LOG,
    "device_evidence_window_count": $DEVICE_EVIDENCE_WINDOWS,
    "openice_running": $OPENICE_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="