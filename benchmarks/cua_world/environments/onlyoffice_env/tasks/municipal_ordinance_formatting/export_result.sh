#!/bin/bash
echo "=== Exporting Municipal Ordinance Formatting Result ==="

source /workspace/scripts/task_utils.sh

# Capture the final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Attempt to gracefully save the document and close ONLYOFFICE
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still running
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi
sleep 1

# Gather output metrics
OUTPUT_PATH="/home/ga/Documents/TextDocuments/str_ordinance_final.docx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo 0)

    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Export metrics to JSON
cat > /tmp/municipal_ordinance_result.json << JSONEOF
{
  "task_name": "municipal_ordinance_formatting",
  "timestamp": $(date +%s),
  "output_file_exists": $FILE_EXISTS,
  "output_file_size": $FILE_SIZE,
  "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
  "start_time": $TASK_START
}
JSONEOF

echo "Result payload exported to /tmp/municipal_ordinance_result.json"
echo "=== Export Complete ==="