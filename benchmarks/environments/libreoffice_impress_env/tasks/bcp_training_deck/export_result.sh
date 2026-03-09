#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting BCP Training Deck Result ==="

su - ga -c "DISPLAY=:1 scrot /tmp/task_final_screenshot.png" || true

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
    safe_xdotool ga :1 key --delay 300 ctrl+s
    sleep 3
    safe_xdotool ga :1 key --delay 200 Return
    sleep 1
fi

if [ -f /home/ga/Documents/Presentations/bcp_training.odp ]; then
    echo "ODP present: $(stat -c%s /home/ga/Documents/Presentations/bcp_training.odp) bytes"
else
    echo "WARNING: ODP not found"
fi

if [ -f /home/ga/Documents/Presentations/bcp_training.pdf ]; then
    echo "PDF present: $(stat -c%s /home/ga/Documents/Presentations/bcp_training.pdf) bytes"
else
    echo "PDF not found"
fi

echo "=== Export Complete ==="
