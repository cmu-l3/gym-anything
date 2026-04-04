#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Silent Auction Results ==="

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
if wait_for_file "/home/ga/Documents/auction_items.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/auction_items.ods"
    ls -lh /home/ga/Documents/auction_items.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Also try to save as auction_results.ods for clarity
echo "Saving copy as auction_results.ods..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1

# Type filename
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/auction_results.ods"
sleep 0.5
safe_xdotool ga :1 key Return
sleep 1

# Handle any overwrite dialog
safe_xdotool ga :1 key Return || true
sleep 0.5

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="
echo "📁 Results should be in:"
echo "   - /home/ga/Documents/auction_items.ods (original)"
echo "   - /home/ga/Documents/auction_results.ods (copy)"