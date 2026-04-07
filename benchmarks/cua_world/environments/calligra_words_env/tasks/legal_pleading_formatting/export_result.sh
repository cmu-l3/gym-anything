#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Legal Pleading Formatting Result ==="

# Bring Calligra to front to capture the final state
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Capture final screenshot for VLM
take_screenshot /tmp/calligra_legal_pleading_post_task.png

if [ -f "/home/ga/Documents/martinez_msj.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/martinez_msj.odt || true
else
    echo "Warning: /home/ga/Documents/martinez_msj.odt is missing"
fi

# Safely shut down Calligra - do NOT force save, agent must have saved manually
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="