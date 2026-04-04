#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Coffee Roast Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS using Save As dialog
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/coffee_roast_tracker.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If there's a confirmation dialog (overwrite), press Enter again
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/coffee_roast_tracker.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/coffee_roast_tracker.ods"
    ls -lh /home/ga/Documents/coffee_roast_tracker.ods || true
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/coffee_roast_log.csv" ]; then
        echo "CSV file exists (may have been modified in place)"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="