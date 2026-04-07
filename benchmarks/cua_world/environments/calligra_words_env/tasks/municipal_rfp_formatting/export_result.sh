#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Municipal RFP Formatting Result ==="

# Focus window and take final screenshot
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
    sleep 0.5
fi

take_screenshot /tmp/calligra_rfp_formatting_post_task.png

if [ -f "/home/ga/Documents/smart_parking_rfp.odt" ]; then
    # Print stat for logging
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/smart_parking_rfp.odt || true
else
    echo "Warning: /home/ga/Documents/smart_parking_rfp.odt is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="