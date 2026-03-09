#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Receipt Reconciliation Result ==="

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

# If it's still CSV, try Save As ODS
# First check if we need to convert
OUTPUT_FILE="/home/ga/Documents/reconciled_receipt.ods"

# Try Save As (Ctrl+Shift+S)
echo "Attempting Save As ODS format..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Handle possible format confirmation dialog
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Check if file was saved
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif [ -f "/home/ga/Documents/grocery_receipt.ods" ]; then
    echo "✅ File saved: /home/ga/Documents/grocery_receipt.ods"
    ls -lh "/home/ga/Documents/grocery_receipt.ods"
elif [ -f "/home/ga/Documents/grocery_receipt.csv" ]; then
    echo "⚠️ File still in CSV format: /home/ga/Documents/grocery_receipt.csv"
    ls -lh "/home/ga/Documents/grocery_receipt.csv"
else
    echo "⚠️ Warning: Output file status unclear"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Handle possible "Save changes?" dialog
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

echo "=== Export Complete ==="