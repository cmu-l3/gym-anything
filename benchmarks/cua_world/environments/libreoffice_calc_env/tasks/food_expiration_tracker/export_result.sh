#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Food Expiration Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS
echo "Saving file as food_inventory_tracker.ods..."

# Use Save As to ensure ODS format
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/food_inventory_tracker.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# If file exists dialog appears, press Enter again to confirm overwrite
safe_xdotool ga :1 key Return
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/food_inventory_tracker.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/food_inventory_tracker.ods"
    ls -lh /home/ga/Documents/food_inventory_tracker.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/food_inventory.csv" ]; then
        echo "⚠️ CSV file exists but may not have been saved as ODS"
        ls -lh /home/ga/Documents/food_inventory.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="