#!/bin/bash
set -euo pipefail

echo "=== Exporting Neuropsychological Evaluation Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus the app to make sure the screenshot is representative (backup)
WID=$(DISPLAY=:1 wmctrl -l | grep -i "WPS Writer" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 scrot /tmp/task_final_focused.png 2>/dev/null || true
fi

# Locate the expected output file
DOC_PATH="/home/ga/Documents/results/final_neuropsych_eval.docx"
DOC_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
DOC_SIZE=0

# Fallbacks in case agent saved somewhere else
if [ ! -f "$DOC_PATH" ]; then
    if [ -f "/home/ga/Documents/final_neuropsych_eval.docx" ]; then
        DOC_PATH="/home/ga/Documents/final_neuropsych_eval.docx"
    elif [ -f "/home/ga/Documents/results/final_neuropsych_eval.wps" ]; then
        DOC_PATH="/home/ga/Documents/results/final_neuropsych_eval.wps"
    elif [ -f "/home/ga/Documents/raw_neuropsych_eval.docx" ]; then
        # They may have just overwritten the original
        DOC_PATH="/home/ga/Documents/raw_neuropsych_eval.docx"
    fi
fi

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    
    if [ "$DOC_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Safely copy for verifier
    cp "$DOC_PATH" /tmp/eval_report_eval.docx
    chmod 666 /tmp/eval_report_eval.docx
fi

APP_RUNNING=$(pgrep -f "wps" > /dev/null && echo "true" || echo "false")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $DOC_EXISTS,
    "document_path": "$DOC_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $DOC_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json

# Close WPS gracefully
if pgrep -f "wps" > /dev/null; then
    su - ga -c "DISPLAY=:1 xdotool key --delay 200 alt+F4" || true
    sleep 2
    su - ga -c "DISPLAY=:1 xdotool key Return" || true  # Confirm exit if asked
fi

echo "=== Export Complete ==="