#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Emergency Supply Rotation Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save as ODS format explicitly
echo "Saving file as ODS..."
# Use Save As to ensure ODS format
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/emergency_supplies.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1.5

# If there's a format confirmation dialog, accept it
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/emergency_supplies.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/emergency_supplies.ods"
    ls -lh /home/ga/Documents/emergency_supplies.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/emergency_supplies_partial.csv" ]; then
        echo "📝 CSV file exists, agent may have worked on CSV directly"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="