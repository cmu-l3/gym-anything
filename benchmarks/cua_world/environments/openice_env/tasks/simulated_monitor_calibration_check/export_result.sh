#!/bin/bash
echo "=== Exporting Simulated Monitor Calibration Check Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (system state)
take_screenshot /tmp/task_final_screenshot.png

# 2. Collect timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check CSV Report
REPORT_PATH="/home/ga/Desktop/calibration_report.csv"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Check creation time
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content for verifier (base64 to avoid JSON breaking)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
fi

# 4. Check Evidence Screenshot (120 BPM)
EVIDENCE_PATH="/home/ga/Desktop/calibration_120bpm.png"
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    # Check if created during task
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING_TASK="true"
    else
        EVIDENCE_CREATED_DURING_TASK="false"
    fi
    # Copy to tmp for potential VLM analysis if needed (though we mostly use final screenshot or trajectory)
    cp "$EVIDENCE_PATH" /tmp/evidence_screenshot.png
fi

# 5. Check Log for Device/App Activity
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get new log lines
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

DEVICE_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "multiparameter|monitor|device.*created|adapter.*started"; then
    DEVICE_CREATED="true"
fi

APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "vital.*signs|app.*launched|clinical"; then
    APP_LAUNCHED="true"
fi

# 6. Check Window State
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

DEVICE_WINDOW_VISIBLE="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter|monitor"; then
    DEVICE_WINDOW_VISIBLE="true"
fi

APP_WINDOW_VISIBLE="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "vital|signs"; then
    APP_WINDOW_VISIBLE="true"
fi

# 7. Check if OpenICE is still running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Create Result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "evidence_screenshot_exists": $EVIDENCE_EXISTS,
    "evidence_path": "$EVIDENCE_PATH",
    "device_created_log": $DEVICE_CREATED,
    "app_launched_log": $APP_LAUNCHED,
    "device_window_visible": $DEVICE_WINDOW_VISIBLE,
    "app_window_visible": $APP_WINDOW_VISIBLE,
    "window_increase": $WINDOW_INCREASE,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "evidence_copy_path": "/tmp/evidence_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json