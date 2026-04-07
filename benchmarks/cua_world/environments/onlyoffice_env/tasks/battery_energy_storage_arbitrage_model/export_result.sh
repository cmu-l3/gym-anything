#!/bin/bash
set -euo pipefail

echo "=== Exporting Battery Energy Storage Arbitrage Model Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot showing agent's work
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Save the document and close ONLYOFFICE cleanly if it's running
if pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null; then
    echo "Saving and closing ONLYOFFICE..."
    WID=$(DISPLAY=:1 wmctrl -l | grep -i 'onlyoffice\|Desktop Editors' | awk '{print $1; exit}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 0.5
        # Ctrl+S to save
        su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
        sleep 2
        # Ctrl+Q to quit
        su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
        sleep 2
    fi
    pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
fi

# Locate the output file
TARGET_PATH="/home/ga/Documents/Spreadsheets/bess_arbitrage_model.xlsx"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$TARGET_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$TARGET_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$TARGET_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "File found: $TARGET_PATH ($OUTPUT_SIZE bytes)"
else
    echo "File not found: $TARGET_PATH"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export completed successfully. Results saved to /tmp/task_result.json"
cat /tmp/task_result.json