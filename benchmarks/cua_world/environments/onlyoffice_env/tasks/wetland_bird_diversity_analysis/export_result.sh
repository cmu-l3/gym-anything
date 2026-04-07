#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Wetland Bird Diversity Analysis Result ==="

# Take final screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/wetland_bird_diversity_analysis_final_screenshot.png" || true

# Try to save the document gracefully
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

EXPECTED_OUTPUT="/home/ga/Documents/Spreadsheets/wetland_diversity_analysis.xlsx"
START_TS=$(cat /tmp/wetland_bird_analysis_start_ts 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")

FILE_CREATED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$START_TS" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "Analysis workbook saved: $EXPECTED_OUTPUT"
    ls -lh "$EXPECTED_OUTPUT"
else
    echo "Analysis workbook not found at expected location: $EXPECTED_OUTPUT"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

cat > /tmp/wetland_bird_diversity_analysis_result.json << JSONEOF
{
  "task_name": "wetland_bird_diversity_analysis",
  "timestamp": $(date +%s),
  "output_file_exists": $([ -f "$EXPECTED_OUTPUT" ] && echo "true" || echo "false"),
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_file_size": $(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="