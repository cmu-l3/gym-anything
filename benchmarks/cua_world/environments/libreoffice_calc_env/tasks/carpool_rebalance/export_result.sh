#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Carpool Rebalance Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with new name using Save As
echo "Saving file as carpool_rebalanced.ods..."

# Ctrl+Shift+S for Save As
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/carpool_rebalanced.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# If there's a confirmation dialog (file exists), press Enter again
safe_xdotool ga :1 key Return
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/carpool_rebalanced.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/carpool_rebalanced.ods"
    ls -lh /home/ga/Documents/carpool_rebalanced.ods || true
else
    # Try to use the original file if Save As didn't work
    if [ -f "/home/ga/Documents/carpool_schedule.ods" ]; then
        echo "⚠️ Using original file (Save As may not have worked)"
        cp /home/ga/Documents/carpool_schedule.ods /home/ga/Documents/carpool_rebalanced.ods 2>/dev/null || true
    else
        echo "⚠️ Warning: File not found or not recently modified"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="