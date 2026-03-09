#!/bin/bash
echo "=== Exporting analytics report results ==="

# Source utils for screenshot
source /workspace/scripts/task_utils.sh

# 1. Basic File Metadata
REPORT_FILE="/home/ga/analytics_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

EXISTS="false"
SIZE="0"
CREATED_DURING_TASK="false"
CONTENT_PREVIEW=""

if [ -f "$REPORT_FILE" ]; then
    EXISTS="true"
    SIZE=$(stat -c%s "$REPORT_FILE")
    MTIME=$(stat -c%Y "$REPORT_FILE")
    
    if [ "$MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Read first 10 lines for debugging log
    CONTENT_PREVIEW=$(head -n 10 "$REPORT_FILE" | base64 -w 0)
fi

# 2. Capture final state
take_screenshot /tmp/task_final.png

# 3. Create Result JSON
# We don't include the full file content here to avoid massive JSONs if the agent dumps a huge log.
# The verifier will copy the actual file using copy_from_env.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "report_exists": $EXISTS,
    "report_size": $SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"