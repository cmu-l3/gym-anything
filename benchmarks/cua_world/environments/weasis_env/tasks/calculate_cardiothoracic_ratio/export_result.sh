#!/bin/bash
echo "=== Exporting calculate_cardiothoracic_ratio task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as UI evidence
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/DICOM/exports/ctr_report.txt"
IMAGE_PATH="/home/ga/DICOM/exports/ctr_measurements.png"

REPORT_EXISTS="false"
REPORT_MODIFIED_DURING_TASK="false"
IMAGE_EXISTS="false"

# Check text report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        REPORT_MODIFIED_DURING_TASK="true"
    fi
fi

# Check image export
if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
fi

# Package into JSON object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_modified_during_task": $REPORT_MODIFIED_DURING_TASK,
    "image_exists": $IMAGE_EXISTS,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="