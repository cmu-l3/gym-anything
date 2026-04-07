#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bilingual Contract Alignment Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# Final Evidence
take_screenshot /tmp/calligra_bilingual_alignment_post_task.png

if [ -f "/home/ga/Documents/bilingual_mnda.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/bilingual_mnda.odt || true
else
    echo "Warning: /home/ga/Documents/bilingual_mnda.odt is missing"
fi

# Close Calligra safely allowing changes to be recorded if the agent clicked save
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="