#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Football Scouting Report Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# Final screenshot
take_screenshot /tmp/calligra_scouting_report_post_task.png

if [ -f "/home/ga/Documents/wildcats_scouting_report.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/wildcats_scouting_report.odt || true
else
    echo "Warning: /home/ga/Documents/wildcats_scouting_report.odt is missing"
fi

# Tell agent to cleanly quit without forcing a save
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

# Create result JSON with modification timestamps for anti-gaming verification
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_MTIME=$(stat -c %Y "/home/ga/Documents/wildcats_scouting_report.odt" 2>/dev/null || echo "0")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_mtime": $OUTPUT_MTIME
}
EOF
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="