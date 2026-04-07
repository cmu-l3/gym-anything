#!/bin/bash
set -euo pipefail

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Capture final UI state
take_screenshot /tmp/task_final.png ga

OUTPUT_PATH="/home/ga/Documents/NOTLD_VO_Script.docx"
OUTPUT_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
OUTPUT_SIZE="0"

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check for output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify the file was created/modified during the task window
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy to /tmp/ for easy extraction by verifier
    cp "$OUTPUT_PATH" /tmp/NOTLD_VO_Script.docx
    chmod 666 /tmp/NOTLD_VO_Script.docx
fi

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json

# Close WPS gracefully
echo "Closing WPS Writer..."
if pgrep -f "wps" > /dev/null; then
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 alt+F4
    sleep 2
    # Deal with any "Save changes?" dialogs
    safe_xdotool ga :1 key --delay 100 Return
    sleep 1
    pkill -f "wps" 2>/dev/null || true
fi

echo "=== Export Complete ==="