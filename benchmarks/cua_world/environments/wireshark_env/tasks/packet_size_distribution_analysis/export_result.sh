#!/bin/bash
set -e
echo "=== Exporting Packet Size Analysis Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/captures/packet_size_report.txt"
GROUND_TRUTH_PATH="/var/lib/wireshark_ground_truth/ground_truth.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence and Timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
fi

# 3. Check if Wireshark is still running
APP_RUNNING="false"
if pgrep -f "wireshark" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Get Ground Truth content
GT_CONTENT=""
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH_PATH" | base64 -w 0)
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "report_content_b64": "$REPORT_CONTENT",
    "ground_truth_b64": "$GT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to public location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"