#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Renovation Budget Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/renovation_budget.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/renovation_budget.ods"
    ls -lh /home/ga/Documents/renovation_budget.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="