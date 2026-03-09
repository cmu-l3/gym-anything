#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Appliance Price Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with Ctrl+S (will save as ODS automatically when imported from CSV)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1.5

# If save dialog appears (Save As), handle it
# Type filename to ensure it's saved as ODS
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/appliance_price_analysis.ods"
sleep 0.5
safe_xdotool ga :1 key Return
sleep 1

# Wait for file to be saved
OUTPUT_FILE="/home/ga/Documents/appliance_price_analysis.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Analysis saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Try alternate locations
    if [ -f "/home/ga/Documents/dishwasher_prices.ods" ]; then
        echo "✅ File saved as: dishwasher_prices.ods"
        ls -lh /home/ga/Documents/dishwasher_prices.ods
    elif [ -f "/home/ga/Documents/dishwasher_prices.csv" ]; then
        echo "⚠️  File exists as CSV (may not have been saved as ODS)"
        ls -lh /home/ga/Documents/dishwasher_prices.csv
    else
        echo "⚠️  Warning: Output file not found or not recently modified"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="