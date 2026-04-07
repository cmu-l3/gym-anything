#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fire Investigation Report Result ==="

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
if [ -f "/home/ga/Documents/fire_investigation_report.odt" ]; then
    OUTPUT_MTIME=$(stat -c %Y "/home/ga/Documents/fire_investigation_report.odt" 2>/dev/null || echo "0")
else
    OUTPUT_MTIME=0
fi

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot BEFORE closing Calligra
take_screenshot /tmp/task_final.png

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_mtime": $OUTPUT_MTIME
}
EOF
chmod 666 /tmp/task_result.json

if [ -f "/home/ga/Documents/fire_investigation_report.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/fire_investigation_report.odt || true
else
    echo "Warning: /home/ga/Documents/fire_investigation_report.odt is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="