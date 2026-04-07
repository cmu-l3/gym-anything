#!/bin/bash
set -euo pipefail

echo "=== Exporting Volcano Hazard Briefing Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Safely close ONLYOFFICE to ensure file buffers are flushed
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    echo "ONLYOFFICE is running, attempting graceful save/close..."
    # Focus window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "onlyoffice" | awk '{print $1}' | head -n 1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 0.5
        # We don't force save here because the user is supposed to "Save As" the Final PPTX.
        # If they didn't do it, they fail. But we close the app.
        DISPLAY=:1 xdotool key ctrl+q 2>/dev/null || true
        sleep 2
    fi
    pkill -f "onlyoffice-desktopeditors" || true
fi

# Gather file info
OUTPUT_PATH="/home/ga/Documents/Presentations/Rainier_Hazard_Briefing_Final.pptx"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
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
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="