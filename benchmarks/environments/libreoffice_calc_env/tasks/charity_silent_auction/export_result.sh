#!/bin/bash
# set -euo pipefail

echo "=== Exporting Charity Silent Auction Result ==="

source /workspace/scripts/task_utils.sh

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/auction_tracker.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/auction_tracker.ods"
    ls -lh /home/ga/Documents/auction_tracker.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="