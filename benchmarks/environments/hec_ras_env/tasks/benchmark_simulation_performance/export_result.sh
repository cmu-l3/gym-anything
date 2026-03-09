#!/bin/bash
echo "=== Exporting benchmark_simulation_performance results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

LOG_PATH="/home/ga/Documents/hec_ras_results/simulation.log"
REPORT_PATH="/home/ga/Documents/hec_ras_results/benchmark_report.csv"

# 1. Check Log File
LOG_EXISTS="false"
LOG_SIZE="0"
LOG_CREATED_DURING_TASK="false"
LOG_CONTENT_HEAD=""

if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_SIZE=$(stat -c %s "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_CREATED_DURING_TASK="true"
    fi
    
    # Capture first few lines to verify it's a RAS log
    LOG_CONTENT_HEAD=$(head -n 20 "$LOG_PATH" | base64 -w 0)
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read the full CSV content
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_exists": $LOG_EXISTS,
    "log_size": $LOG_SIZE,
    "log_created_during_task": $LOG_CREATED_DURING_TASK,
    "log_content_head_b64": "$LOG_CONTENT_HEAD",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"