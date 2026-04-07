#!/bin/bash
echo "=== Exporting Longitudinal Physiological Sampling result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ---------------------------------------------------------
# CHECK FILES
# ---------------------------------------------------------
CSV_PATH="/home/ga/Desktop/monitor_sample.csv"
REPORT_PATH="/home/ga/Desktop/sample_analysis.txt"

# Check CSV
CSV_EXISTS="false"
CSV_MTIME="0"
CSV_SIZE="0"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Check Report
REPORT_EXISTS="false"
REPORT_MTIME="0"
REPORT_SIZE="0"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# ---------------------------------------------------------
# CHECK OPENICE STATE
# ---------------------------------------------------------
# Check if OpenICE is running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Check for Multiparameter Monitor in logs (new lines only)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

DEVICE_CREATED="false"
# Look for indicators of Multiparameter monitor creation
if echo "$NEW_LOG" | grep -qiE "Multiparameter|MultiParam|Vital.*Monitor|DeviceAdapter.*Created"; then
    DEVICE_CREATED="true"
fi

# Backup check using window titles
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Multiparameter|Monitor"; then
    DEVICE_CREATED="true"
fi

# ---------------------------------------------------------
# CREATE RESULT JSON
# ---------------------------------------------------------
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_mtime": $CSV_MTIME,
    "csv_size": $CSV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_size": $REPORT_SIZE,
    "openice_running": $OPENICE_RUNNING,
    "device_created": $DEVICE_CREATED,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Ensure permissions on user files so verifier can read them if needed
if [ -f "$CSV_PATH" ]; then chmod 644 "$CSV_PATH"; fi
if [ -f "$REPORT_PATH" ]; then chmod 644 "$REPORT_PATH"; fi

echo "=== Result exported ==="
cat /tmp/task_result.json