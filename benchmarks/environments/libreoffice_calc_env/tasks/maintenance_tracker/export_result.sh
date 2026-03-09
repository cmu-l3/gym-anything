#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Maintenance Tracker Result ==="

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+Shift+S for Save As)
echo "Saving as ODS file..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/maintenance_tracker_complete.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# Handle potential "confirm overwrite" dialog (press Enter again)
safe_xdotool ga :1 key Return
sleep 0.5

# Also do regular save (Ctrl+S) to ensure changes are saved
echo "Saving file (Ctrl+S)..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if file was saved
if wait_for_file "/home/ga/Documents/maintenance_tracker_complete.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/maintenance_tracker_complete.ods"
    ls -lh /home/ga/Documents/maintenance_tracker_complete.ods
elif wait_for_file "/home/ga/Documents/maintenance_log.ods" 5; then
    echo "✅ File saved as: /home/ga/Documents/maintenance_log.ods"
    ls -lh /home/ga/Documents/maintenance_log.ods
else
    echo "⚠️ Warning: ODS file not found, checking CSV..."
    if [ -f "/home/ga/Documents/maintenance_log.csv" ]; then
        echo "⚠️ CSV file exists (may not have been saved as ODS)"
        ls -lh /home/ga/Documents/maintenance_log.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="