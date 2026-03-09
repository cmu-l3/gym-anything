#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Car Maintenance Tracker Result ==="

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

# Try Save As to ensure ODS format
echo "Ensuring ODS format (Save As)..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/car_maintenance_analyzed.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# Handle "file exists" dialog if present (press Enter to confirm overwrite)
safe_xdotool ga :1 key Return
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/car_maintenance_analyzed.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/car_maintenance_analyzed.ods"
    ls -lh /home/ga/Documents/car_maintenance_analyzed.ods
else
    echo "⚠️ Primary file not found, checking alternatives..."
    # Check for original file
    if [ -f "/home/ga/Documents/car_maintenance_log.ods" ]; then
        echo "✅ Original ODS file exists: /home/ga/Documents/car_maintenance_log.ods"
        ls -lh /home/ga/Documents/car_maintenance_log.ods
    elif [ -f "/home/ga/Documents/car_maintenance_log.csv" ]; then
        echo "⚠️ Only CSV exists: /home/ga/Documents/car_maintenance_log.csv"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Handle "Save changes?" dialog if present (press N for No, since we already saved)
safe_xdotool ga :1 key n
sleep 0.3

echo "=== Export Complete ==="