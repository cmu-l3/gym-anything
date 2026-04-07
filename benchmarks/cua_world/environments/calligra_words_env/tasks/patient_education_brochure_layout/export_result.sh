#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Patient Education Brochure Layout Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Stat the saved file if it exists
OUTPUT_FILE="/home/ga/Documents/heart_failure_brochure_print.odt"
if [ -f "$OUTPUT_FILE" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "$OUTPUT_FILE" || true
else
    echo "Warning: $OUTPUT_FILE is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="