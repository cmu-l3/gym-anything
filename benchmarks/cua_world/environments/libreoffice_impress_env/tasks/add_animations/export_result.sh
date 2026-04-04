#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Animations Result ==="

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

safe_xdotool ga :1 key --delay 200 ctrl+s
wait_for_file "/home/ga/Documents/Presentations/animation_test.odp" 5
safe_xdotool ga :1 key --delay 200 ctrl+q

echo "=== Export Complete ==="
