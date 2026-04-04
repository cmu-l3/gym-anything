#!/bin/bash
set -e
echo "=== Exporting TCP Conversation Profiling results ==="

source /workspace/scripts/task_utils.sh

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REPORT_FILE="/home/ga/Documents/captures/tcp_conversation_report.txt"
CSV_FILE="/home/ga/Documents/captures/tcp_conversations.csv"
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Files Existence and Modification Times
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_IN_TASK="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0) # Base64 encode to safely put in JSON
    MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_IN_TASK="true"
    fi
fi

CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_CREATED_IN_TASK="false"
CSV_HEADER=""
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    # Count rows excluding header
    CSV_ROW_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l)
    CSV_HEADER=$(head -n 1 "$CSV_FILE")
    MTIME=$(stat -c %Y "$CSV_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_IN_TASK="true"
    fi
fi

# 2. Read Ground Truth
GT_TOTAL=$(cat "$GROUND_TRUTH_DIR/total_conversations.txt" 2>/dev/null || echo "0")
GT_AVG=$(cat "$GROUND_TRUTH_DIR/average_duration.txt" 2>/dev/null || echo "0")
GT_LONGEST=$(cat "$GROUND_TRUTH_DIR/longest_duration.txt" 2>/dev/null || echo "")
GT_HIGHEST=$(cat "$GROUND_TRUTH_DIR/highest_volume.txt" 2>/dev/null || echo "")

# 3. Check if Wireshark is still running
APP_RUNNING="false"
if pgrep -f wireshark > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "report_file": {
        "exists": $REPORT_EXISTS,
        "created_in_task": $REPORT_CREATED_IN_TASK,
        "content_base64": "$REPORT_CONTENT"
    },
    "csv_file": {
        "exists": $CSV_EXISTS,
        "created_in_task": $CSV_CREATED_IN_TASK,
        "row_count": $CSV_ROW_COUNT,
        "header": "$(echo "$CSV_HEADER" | sed 's/"/\\"/g')"
    },
    "ground_truth": {
        "total_conversations": $GT_TOTAL,
        "average_duration": "$GT_AVG",
        "longest_info": "$GT_LONGEST",
        "highest_info": "$GT_HIGHEST"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="