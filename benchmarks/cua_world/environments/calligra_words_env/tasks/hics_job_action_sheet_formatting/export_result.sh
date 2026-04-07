#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting HICS Job Action Sheet Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Capture final screenshot before terminating application
take_screenshot /tmp/calligra_hics_jas_formatting_post_task.png

if [ -f "/home/ga/Documents/hics_jas_formatted.odt" ]; then
    echo "Found properly named output file."
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/hics_jas_formatted.odt || true
elif [ -f "/home/ga/Documents/hics_jas_raw.odt" ]; then
    echo "Output file strictly named 'hics_jas_formatted.odt' not found, will fallback to 'hics_jas_raw.odt' for verification."
    stat -c "Fallback file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/hics_jas_raw.odt || true
else
    echo "Warning: Expected document is missing entirely."
fi

# Do not force-save. The agent must successfully trigger the save.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="