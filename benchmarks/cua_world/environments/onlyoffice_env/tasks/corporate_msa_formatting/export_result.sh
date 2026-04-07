#!/bin/bash
set -euo pipefail

echo "=== Exporting Corporate MSA Formatting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing what the agent accomplished
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Save and close cleanly if STILL running
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi
kill_onlyoffice ga
sleep 1

# Gather metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/TextDocuments/formatted_msa_final.docx"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json