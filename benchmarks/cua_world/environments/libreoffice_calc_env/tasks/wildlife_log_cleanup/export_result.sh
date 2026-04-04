#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Wildlife Log Cleanup Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Ensure we're on the Observations sheet
echo "Ensuring Observations sheet is active..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/wildlife_observations.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/wildlife_observations.ods"
    ls -lh /home/ga/Documents/wildlife_observations.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="