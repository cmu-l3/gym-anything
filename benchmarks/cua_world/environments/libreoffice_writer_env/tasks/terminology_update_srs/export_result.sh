#!/bin/bash
# export_result.sh - Terminology Update SRS

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Terminology Update Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/CloudBridge_SRS_v3.0.docx"
ORIGINAL_FILE="/home/ga/Documents/DataSync_SRS_v2.3.docx"

# 1. Close LibreOffice Writer gracefully to ensure file buffers are flushed
# We attempt to close via WM first, then kill if needed
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Closing LibreOffice Writer..."
    focus_window "$WID"
    # Ctrl+Q to quit
    safe_xdotool ga :1 key ctrl+q
    sleep 2
    
    # Handle "Save changes?" dialog if it appears (Press Enter to Save if they haven't, 
    # or Esc/Don't Save? 
    # Actually, we want to capture the state AS IS. If the agent didn't save, the file won't exist.
    # We should just close. If a dialog appears, it means unsaved changes.
    # We'll press 'Right' then 'Enter' to select "Don't Save" to close the app,
    # because we rely on the file on disk.
    safe_xdotool ga :1 key Right
    safe_xdotool ga :1 key Return
    sleep 1
fi
pkill -f "soffice" || true

# 2. Check Output File Status
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Original File Status (should still exist)
ORIGINAL_EXISTS="false"
if [ -f "$ORIGINAL_FILE" ]; then
    ORIGINAL_EXISTS="true"
fi

# 4. Take final screenshot (desktop view since app is closed, or re-open?)
# Actually, the framework usually takes screenshots during execution. 
# We'll take one of the desktop to show file icons if possible, but mainly rely on file analysis.
take_screenshot /tmp/task_final.png

# 5. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "original_exists": $ORIGINAL_EXISTS,
    "output_path": "$OUTPUT_FILE",
    "original_path": "$ORIGINAL_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json