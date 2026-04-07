#!/bin/bash
set -euo pipefail

echo "=== Exporting professional_correspondence_formatting result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing
take_screenshot /tmp/task_final_state.png

# Bring window to front
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# We don't force save so the agent's work isn't altered if they didn't save.
# Just cleanly exit.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export complete ==="