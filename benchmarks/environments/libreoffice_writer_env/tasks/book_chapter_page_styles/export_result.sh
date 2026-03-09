#!/bin/bash
# export_result.sh - Book Chapter Manuscript Page Styles

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/chapter1_formatted.docx"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if output file exists
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

# Close LibreOffice Writer gracefully if possible
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ctrl+Q to quit
    safe_xdotool ga :1 key ctrl+q
    sleep 1
    # If "Save changes?" dialog appears, press "Don't Save" (Alt+D)
    # We expect the agent to have saved to a NEW file already.
    safe_xdotool ga :1 key alt+d 2>/dev/null || true
fi

echo "=== Export complete ==="