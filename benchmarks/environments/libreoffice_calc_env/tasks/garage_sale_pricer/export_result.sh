#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Garage Sale Pricing Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Open Save As dialog (Ctrl+Shift+S)
echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
echo "Setting filename..."
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/garage_sale_pricing.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1.5

# Handle potential overwrite dialog
safe_xdotool ga :1 key --delay 200 Return || true
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/garage_sale_pricing.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/garage_sale_pricing.ods"
    ls -lh /home/ga/Documents/garage_sale_pricing.ods
else
    echo "⚠️ Warning: garage_sale_pricing.ods not found"
    # Try to save the currently open file as fallback
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="