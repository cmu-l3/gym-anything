#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Terminology Standardization Result ==="

# Focus Calligra if possible to capture its final state correctly
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

take_screenshot /tmp/task_final.png

if [ -f "/home/ga/Documents/clinical_study_report.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/clinical_study_report.odt || true
else
    echo "Warning: /home/ga/Documents/clinical_study_report.odt is missing"
fi

# Close calligra cleanly so the agent's work isn't discarded if it forgot to save
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="