#!/bin/bash
set -euo pipefail

echo "=== Exporting Exoplanet Transit Analysis Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Ensure spreadsheet is saved properly
if pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -i 'ONLYOFFICE\|Desktop Editors' | awk '{print $1; exit}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        # Send Ctrl+S to save
        su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" 2>/dev/null || true
        sleep 2
    fi
fi

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check output file
OUTPUT_PATH="/home/ga/Documents/Spreadsheets/kepler8b_analysis.xlsx"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Check if they saved it as CSV by accident or in wrong folder
    ALT_PATH=$(find /home/ga/Documents -name "*kepler8b_analysis*.xlsx" -type f | head -n 1)
    if [ -n "$ALT_PATH" ] && [ -f "$ALT_PATH" ]; then
        OUTPUT_EXISTS="true"
        OUTPUT_SIZE=$(stat -c %s "$ALT_PATH" 2>/dev/null || echo "0")
        OUTPUT_MTIME=$(stat -c %Y "$ALT_PATH" 2>/dev/null || echo "0")
        if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        # Copy to expected path for verifier
        cp "$ALT_PATH" "$OUTPUT_PATH"
    fi
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="