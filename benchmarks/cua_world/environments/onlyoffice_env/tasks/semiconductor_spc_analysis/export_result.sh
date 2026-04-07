#!/bin/bash
set -euo pipefail

echo "=== Exporting Semiconductor SPC Analysis Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot before closing
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true
sleep 1

# Attempt to save and close gracefully if OnlyOffice is active
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    # Bring to front
    DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true
    sleep 0.5
    # Send Ctrl+S to ensure save
    su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
    sleep 2
    # Send Ctrl+Q to quit
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
fi

# Force kill if still running
pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true

# Check output file
OUTPUT_PATH="/home/ga/Documents/Spreadsheets/wafer_spc_analysis.xlsx"
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

# Create JSON result
TEMP_JSON=$(mktemp /tmp/spc_result.XXXXXX.json)
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

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="