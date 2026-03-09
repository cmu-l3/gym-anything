#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Photography Gear Depreciation Result ==="

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

# Also save as ODS with specific name in case they didn't name it
OUTPUT_FILE="/home/ga/Documents/gear_depreciation_report.ods"

# Try Save As
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to confirm
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If format dialog appears, confirm ODS format
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

# Wait for file to be saved
if wait_for_file "$OUTPUT_FILE" 3; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Check if original CSV was modified
    if [ -f "/home/ga/Documents/photography_gear_messy.csv" ]; then
        echo "⚠️ Checking original CSV location"
    fi
    # Check if saved as ODS with original name
    if [ -f "/home/ga/Documents/photography_gear_messy.ods" ]; then
        echo "✅ File saved as: /home/ga/Documents/photography_gear_messy.ods"
    else
        echo "⚠️ Warning: Expected output file not found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# If "Save changes?" dialog appears, click Yes
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

echo "=== Export Complete ==="