#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting IT Helpdesk SLA Analysis Result ==="

# Record final state screen
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" || true

# Save the document and gracefully close ONLYOFFICE if running
if is_onlyoffice_running; then
    echo "Attempting to save document..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 3
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still lingering
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

EXPECTED_OUTPUT="/home/ga/Documents/Spreadsheets/q3_sla_performance.xlsx"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"

if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "Output file found: $EXPECTED_OUTPUT"
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo 0)
else
    echo "Output file NOT found at: $EXPECTED_OUTPUT"
    # Agent might have saved it elsewhere or with a typo
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

TASK_START=$(cat /tmp/it_helpdesk_sla_analysis_start_ts 2>/dev/null || echo 0)

cat > /tmp/task_result.json << JSONEOF
{
  "task_name": "it_helpdesk_sla_analysis",
  "task_start_ts": $TASK_START,
  "export_ts": $(date +%s),
  "output_file_exists": $FILE_EXISTS,
  "output_file_size": $FILE_SIZE,
  "output_file_mtime": $FILE_MTIME
}
JSONEOF

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="