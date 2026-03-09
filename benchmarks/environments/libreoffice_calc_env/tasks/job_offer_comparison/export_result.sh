#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Job Offer Comparison Result ==="

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
if wait_for_file "/home/ga/Documents/job_search_tracker.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/job_search_tracker.ods"
    ls -lh /home/ga/Documents/job_search_tracker.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Verify closure
if ! pgrep -f "soffice.*calc" > /dev/null; then
    echo "✅ LibreOffice Calc closed successfully"
else
    echo "⚠️ LibreOffice may still be running"
fi

echo "=== Export Complete ==="