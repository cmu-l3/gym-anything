#!/bin/bash
set -e
echo "=== Exporting medical_device_network_security_review results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# --- 1. Gather Timing Data ---
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# --- 2. Analyze Log for Device Creation ---
# Only check lines added during the task
OPENICE_LOG="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size.txt 2>/dev/null || echo "0")
NEW_LOG_LINES=""

if [ -f "$OPENICE_LOG" ]; then
    CURRENT_LOG_SIZE=$(stat -c%s "$OPENICE_LOG" 2>/dev/null || echo "0")
    if [ "$CURRENT_LOG_SIZE" -gt "$INITIAL_LOG_SIZE" ]; then
        # Extract new lines
        NEW_LOG_LINES=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$OPENICE_LOG")
    fi
fi

# Check for keywords indicating device creation in logs
DEVICE_CREATED_LOG="false"
if echo "$NEW_LOG_LINES" | grep -qiE "simulated|simulator|device.*adapter|multiparameter|monitor|infusion|pump|pulse.*ox|capno|co2|nibp|ecg|ibp|temperature"; then
    DEVICE_CREATED_LOG="true"
fi

# --- 3. Analyze Windows for Device Creation ---
DISPLAY=:1 wmctrl -l 2>/dev/null > /tmp/final_windows.txt || true
INITIAL_WINDOW_COUNT=$(cat /tmp/initial_window_count.txt 2>/dev/null || echo "0")
FINAL_WINDOW_COUNT=$(wc -l < /tmp/final_windows.txt)
WINDOW_INCREASE=$((FINAL_WINDOW_COUNT - INITIAL_WINDOW_COUNT))

DEVICE_CREATED_WINDOW="false"
# Check if any window title contains device keywords
if grep -qiE "simulated|simulator|device|monitor|pump|pulse|capno|nibp|ecg|ibp" /tmp/final_windows.txt; then
    DEVICE_CREATED_WINDOW="true"
fi

# --- 4. Process the Report File ---
REPORT_FILE="/home/ga/Desktop/openice_security_assessment.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    # Read content safely into a variable for JSON embedding
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# Check if report was modified after task start
REPORT_WRITTEN_DURING_TASK="false"
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_WRITTEN_DURING_TASK="true"
fi

# --- 5. Construct Result JSON ---
# We use Python to safely dump the JSON, especially the large string content
python3 -c "
import json
import os
import sys

data = {
    'task_start': int('$TASK_START'),
    'current_time': int('$CURRENT_TIME'),
    'device_created_log': '$DEVICE_CREATED_LOG' == 'true',
    'device_created_window': '$DEVICE_CREATED_WINDOW' == 'true',
    'window_increase': int('$WINDOW_INCREASE'),
    'report': {
        'exists': '$REPORT_EXISTS' == 'true',
        'size': int('$REPORT_SIZE'),
        'written_during_task': '$REPORT_WRITTEN_DURING_TASK' == 'true',
        'content': sys.stdin.read()
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
" <<< "$REPORT_CONTENT"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"