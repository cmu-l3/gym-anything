#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Raffle Ticket Validator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with Ctrl+S
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Additional save as ODS to ensure we have the right format
echo "Saving as ODS format..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1.5

# Type the output filename
OUTPUT_FILE="/home/ga/Documents/raffle_validated.ods"
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to confirm
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If there's a confirmation dialog (file exists), press Enter again
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

# Wait for file to be saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/raffle_sales_raw.csv" ]; then
        echo "✅ CSV file exists and may have been modified"
        ls -lh /home/ga/Documents/raffle_sales_raw.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="