#!/bin/bash
set -euo pipefail

echo "=== Exporting Transit Ridership Analysis Result ==="

TASK_START=$(cat /tmp/transit_task_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot before closing
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null" || true
sleep 1

# Attempt to save the document if OnlyOffice is still active
if pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null; then
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 1
    # Send Ctrl+S to save
    su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
    sleep 3
    # Graceful close
    pkill -TERM -f "onlyoffice-desktopeditors|DesktopEditors" || true
    sleep 2
fi

# Force kill if still hanging
if pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null; then
    pkill -KILL -f "onlyoffice-desktopeditors|DesktopEditors" || true
fi
sleep 1

REPORT_PATH="/home/ga/Documents/Spreadsheets/transit_performance_q1.xlsx"

FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Workbook saved: $REPORT_PATH (Size: $OUTPUT_SIZE bytes)"
else
    echo "Workbook not found at exact path: $REPORT_PATH"
fi

# Create result payload for Python verifier
TEMP_JSON=$(mktemp /tmp/transit_result.XXXXXX.json)
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

# Make readable to verifier
mv "$TEMP_JSON" /tmp/transit_result.json
chmod 666 /tmp/transit_result.json

echo "=== Export Complete ==="