#!/bin/bash
# export_result.sh - Newsletter Linked Frames Flow

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Close LibreOffice Writer gracefully
# Press Ctrl+Q
safe_xdotool ga :1 key ctrl+q
sleep 1
# If "Save changes?" dialog appears, press Enter (Save) or Alt+S if needed
# But usually the agent should have saved. We'll press Esc just in case a dialog is blocking.
safe_xdotool ga :1 key Escape 2>/dev/null || true

# 3. Collect File Stats
OUTPUT_FILE="/home/ga/Documents/newsletter_final.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Create JSON Result
cat << EOF > /tmp/task_result.json
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json