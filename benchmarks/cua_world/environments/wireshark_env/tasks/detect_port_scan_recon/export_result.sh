#!/bin/bash
set -e

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/scan_forensic_report.txt"
GROUND_TRUTH_PATH="/tmp/ground_truth.json"

# Check report existence and timestamps
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content safely, escaping backslashes and double quotes for JSON
    REPORT_CONTENT=$(cat "$REPORT_PATH" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
fi

# Check if Wireshark is still running
WIRESHARK_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare Ground Truth
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH_JSON=$(cat "$GROUND_TRUTH_PATH")
else
    GROUND_TRUTH_JSON="{}"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_raw": "$REPORT_CONTENT",
    "wireshark_running": $WIRESHARK_RUNNING,
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="