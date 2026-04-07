#!/bin/bash
set -euo pipefail

echo "=== Exporting Medical Grand Rounds Presentation Result ==="

# Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Ensure ONLYOFFICE saves any unsaved work (Ctrl+S equivalent via xdotool if focused)
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 1
    # We rely on the agent saving the file, but we'll try an automated save just in case
    # ONLYOFFICE might pop up a save dialog if it hasn't been saved yet, so we don't force it here 
    # to avoid breaking the expected output path if the agent did it correctly.
fi

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if the output file exists
OUTPUT_PATH="/home/ga/Documents/Presentations/grand_rounds_takotsubo.pptx"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if application is running
APP_RUNNING="false"
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    APP_RUNNING="true"
    # Kill it cleanly after capturing state
    pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/medical_task_result.json 2>/dev/null || sudo rm -f /tmp/medical_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/medical_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/medical_task_result.json
chmod 666 /tmp/medical_task_result.json 2>/dev/null || sudo chmod 666 /tmp/medical_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/medical_task_result.json"
cat /tmp/medical_task_result.json
echo "=== Export complete ==="