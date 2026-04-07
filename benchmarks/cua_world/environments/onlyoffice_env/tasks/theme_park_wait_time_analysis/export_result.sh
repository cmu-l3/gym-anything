#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Theme Park Wait Time Analysis Result ==="

# Capture final state
su - ga -c "DISPLAY=:1 import -window root /tmp/theme_park_wait_time_analysis_final_screenshot.png" || true

# Save and close application if it is running
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Hard kill if still lingering
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

# Check for expected output file
REPORT_PATH="/home/ga/Documents/Spreadsheets/theme_park_queue_analysis.xlsx"

if [ -f "$REPORT_PATH" ]; then
    echo "Report found: $REPORT_PATH"
    ls -lh "$REPORT_PATH"
else
    echo "Report not found at exact path. Checking alternatives..."
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

# Export metrics
cat > /tmp/theme_park_wait_time_analysis_result.json << JSONEOF
{
  "task_name": "theme_park_wait_time_analysis",
  "task_end_ts": $(date +%s),
  "output_file_exists": $([ -f "$REPORT_PATH" ] && echo "true" || echo "false"),
  "output_file_size": $(stat -c%s "$REPORT_PATH" 2>/dev/null || echo 0),
  "output_mtime": $(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="