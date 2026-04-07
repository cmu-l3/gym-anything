#!/bin/bash
echo "=== Exporting asynchronous_slice_comparison task result ==="

source /workspace/scripts/task_utils.sh

# Capture final fallback screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"

SCREENSHOT_PATH="$EXPORT_DIR/async_comparison.png"
TEXT_PATH="$EXPORT_DIR/task_complete.txt"

SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED="false"
TEXT_EXISTS="false"
TEXT_CREATED="false"
TEXT_CORRECT="false"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED="true"
    fi
fi

if [ -f "$TEXT_PATH" ]; then
    TEXT_EXISTS="true"
    MTIME=$(stat -c %Y "$TEXT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED="true"
    fi
    if grep -q "async_done" "$TEXT_PATH"; then
        TEXT_CORRECT="true"
    fi
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created_during_task": $SCREENSHOT_CREATED,
    "text_exists": $TEXT_EXISTS,
    "text_created_during_task": $TEXT_CREATED,
    "text_correct": $TEXT_CORRECT,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="