#!/bin/bash
echo "=== Exporting export_filtered_leads_to_csv results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/export_leads_final.png

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/healthcare_leads.csv"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
fi

# Write results to JSON
RESULT_JSON=$(cat << JSONEOF
{
  "file_exists": ${FILE_EXISTS},
  "file_size": ${FILE_SIZE},
  "file_mtime": ${FILE_MTIME},
  "task_start_time": ${TASK_START}
}
JSONEOF
)

safe_write_result "/tmp/export_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/export_result.json"
echo "$RESULT_JSON"
echo "=== export_filtered_leads_to_csv export complete ==="