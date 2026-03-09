#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Credit Card Rewards Optimizer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/credit_card_optimizer.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/credit_card_optimizer.ods"
    ls -lh /home/ga/Documents/credit_card_optimizer.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
    # Try alternative save method (Save As)
    echo "Attempting Save As..."
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    
    # Type filename
    safe_xdotool ga :1 key ctrl+a
    sleep 0.3
    safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/credit_card_optimizer.ods"
    sleep 0.5
    safe_xdotool ga :1 key Return
    sleep 1
    
    # Confirm overwrite if needed
    safe_xdotool ga :1 key Return
    sleep 0.5
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# If Calc didn't close, force close
if pgrep -f "soffice.*calc" > /dev/null; then
    echo "Force closing LibreOffice Calc..."
    pkill -f "soffice.*calc" || true
    sleep 1
fi

echo "=== Export Complete ==="