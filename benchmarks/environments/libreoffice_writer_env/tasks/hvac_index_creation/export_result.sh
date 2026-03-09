#!/bin/bash
# export_result.sh — HVAC Index Creation Task

source /workspace/scripts/task_utils.sh

echo "=== Exporting HVAC Index Result ==="

OUTPUT_PATH="/home/ga/Documents/hvac_manual_indexed.docx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if output file exists and gather stats
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_NEW="true"
    else
        FILE_NEW="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE=0
    FILE_NEW="false"
fi

# 2. Check if Writer is still running
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
    
    # Close Writer gracefully if possible
    wid=$(get_writer_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        # Attempt to save if they haven't? No, strict verification says output must exist.
        # Just close.
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 1
        # Dismiss "Save changes?" if it appears (Don't Save) to avoid hanging
        safe_xdotool ga :1 key --delay 100 alt+d 2>/dev/null || true
    fi
else
    APP_RUNNING="false"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_NEW,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="