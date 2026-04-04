#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Rebate Deadline Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check if original file was updated
if wait_for_file "/home/ga/Documents/rebate_tracker.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/rebate_tracker.ods"
    ls -lh /home/ga/Documents/rebate_tracker.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Also check for alternative save names
if [ -f "/home/ga/Documents/rebate_tracker_completed.ods" ]; then
    echo "✅ Found completed file: rebate_tracker_completed.ods"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="