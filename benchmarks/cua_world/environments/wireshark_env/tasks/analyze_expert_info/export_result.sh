#!/bin/bash
set -e
echo "=== Exporting Expert Info Analysis results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_FILE="/home/ga/Documents/captures/expert_info_report.txt"
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if report file exists
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Read content safely (limit size to prevent massive JSON)
    REPORT_CONTENT=$(head -n 100 "$REPORT_FILE" | base64 -w 0)
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Read ground truth data
GT_JSON=$(cat "$GROUND_TRUTH_DIR/ground_truth.json" 2>/dev/null || echo "{}")
GT_TOP_MSGS=$(head -n 5 "$GROUND_TRUTH_DIR/message_counts.txt" | base64 -w 0)

# Check if Wireshark is running
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "ground_truth_stats": $GT_JSON,
    "ground_truth_top_msgs_base64": "$GT_TOP_MSGS",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="