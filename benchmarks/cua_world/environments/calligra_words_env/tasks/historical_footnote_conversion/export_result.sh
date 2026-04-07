#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Historical Footnote Conversion Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# Capture final state screenshot before any cleanup
take_screenshot /tmp/calligra_historical_footnote_conversion_post_task.png

if [ -f "/home/ga/Documents/triangle_fire_essay.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/triangle_fire_essay.odt || true
else
    echo "Warning: /home/ga/Documents/triangle_fire_essay.odt is missing"
fi

# Attempt to quit cleanly allowing the agent a chance to be saved if unsaved prompts appear
# We don't force save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

# Force kill any lingering instances to ensure file lock is released
kill_calligra_processes

echo "=== Export Complete ==="