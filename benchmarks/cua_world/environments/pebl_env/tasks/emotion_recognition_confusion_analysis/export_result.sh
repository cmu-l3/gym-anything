#!/bin/bash
echo "=== Exporting emotion_recognition_confusion_analysis result ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/pebl/analysis/emotion_report.json"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Export metadata securely for verifier.py
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK
}
EOF
cp "$TEMP_JSON" /tmp/task_meta.json
chmod 666 /tmp/task_meta.json
rm -f "$TEMP_JSON"

# Take final evidence screenshot
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
scrot /tmp/emotion_final_screenshot.png 2>/dev/null || true

echo "=== Export complete ==="