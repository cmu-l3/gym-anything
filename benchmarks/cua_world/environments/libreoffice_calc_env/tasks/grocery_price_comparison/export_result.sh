#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Grocery Price Comparison Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file (Ctrl+S) - will save as ODS in same location
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Also try Save As to ensure ODS format
echo "Ensuring ODS format..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing path and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/grocery_comparison.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If overwrite dialog appears, confirm
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/grocery_comparison.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/grocery_comparison.ods"
    ls -lh /home/ga/Documents/grocery_comparison.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/grocery_data.csv" ]; then
        echo "✅ CSV file exists: /home/ga/Documents/grocery_data.csv"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="