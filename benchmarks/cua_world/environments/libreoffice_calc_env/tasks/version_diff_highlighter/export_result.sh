#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Version Diff Highlighter Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Make sure we're on Version 2 sheet (where highlighting should be)
echo "Ensuring Version 2 sheet is active..."
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.3

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/version_comparison.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/version_comparison.ods"
    ls -lh /home/ga/Documents/version_comparison.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="