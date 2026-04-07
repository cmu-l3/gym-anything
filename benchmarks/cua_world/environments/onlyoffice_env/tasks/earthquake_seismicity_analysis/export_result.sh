#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Earthquake Seismicity Analysis Result ==="

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/earthquake_seismicity_analysis_final.png 2>/dev/null || \
    su - ga -c "DISPLAY=:1 import -window root /tmp/earthquake_seismicity_analysis_final.png" || true

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

REPORT_PATH="/home/ga/Documents/Spreadsheets/seismicity_analysis.xlsx"
OUTPUT_PATH="$REPORT_PATH"

# Gather file metrics
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    echo "Seismicity report saved: $REPORT_PATH"
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo 0)
    ls -lh "$REPORT_PATH"
else
    echo "Seismicity report not found: $REPORT_PATH"
    # Check if they saved it somewhere else
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

# Write results to JSON for the verifier to consume
cat > /tmp/earthquake_seismicity_result.json << JSONEOF
{
  "task_name": "earthquake_seismicity_analysis",
  "task_start_ts": $(cat /tmp/earthquake_task_start_ts 2>/dev/null || echo 0),
  "timestamp": $(date +%s),
  "output_file_exists": $FILE_EXISTS,
  "output_file_size": $FILE_SIZE,
  "output_file_mtime": $FILE_MTIME
}
JSONEOF

echo "=== Export Complete ==="