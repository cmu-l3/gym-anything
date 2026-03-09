#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Clothing Swap Credits Result ==="

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

# Wait for file to be saved/updated
if wait_for_file "/home/ga/Documents/clothing_swap_credits.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/clothing_swap_credits.ods"
    ls -lh /home/ga/Documents/clothing_swap_credits.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Verify file exists
if [ -f "/home/ga/Documents/clothing_swap_credits.ods" ]; then
    echo "✅ Export successful"
else
    echo "❌ Export may have failed - file not found"
fi

echo "=== Export Complete ==="