#!/bin/bash
echo "=== Exporting Corner Illumination Uniformity Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

REPORT_PATH="/home/ga/AstroImages/uniformity_check/uniformity_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_EXISTS="false"
CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Read up to 2KB to prevent massive file payload
    REPORT_CONTENT=$(head -c 2048 "$REPORT_PATH" | sed 's/"/\\"/g' | tr '\n' '|')
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "report_content_raw": "$REPORT_CONTENT",
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy out
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json

# Close AstroImageJ
close_astroimagej

echo "=== Export Complete ==="