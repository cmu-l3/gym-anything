#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Retail Markdown Optimization Result ==="

# Take final screenshot BEFORE closing
su - ga -c "DISPLAY=:1 scrot /tmp/retail_markdown_final.png" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 import -window root /tmp/retail_markdown_final.png" 2>/dev/null || true

# Try to save and close gracefully
if is_onlyoffice_running; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "Desktop Editors\|ONLYOFFICE" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 0.5
        su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
        sleep 3
        su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
        sleep 2
    fi
fi

# Force kill if still running
kill_onlyoffice ga
sleep 1

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/markdown_analysis.xlsx"
TASK_START=$(cat /tmp/retail_markdown_start_ts 2>/dev/null || echo "0")

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
fi

# Export info
cat > /tmp/retail_markdown_result.json << JSONEOF
{
  "task_name": "retail_markdown_optimization",
  "task_start_time": $TASK_START,
  "timestamp": $(date +%s),
  "output_file_exists": $OUTPUT_EXISTS,
  "output_file_size": $OUTPUT_SIZE,
  "output_mtime": $OUTPUT_MTIME
}
JSONEOF

echo "Result JSON saved to /tmp/retail_markdown_result.json"
echo "=== Export Complete ==="