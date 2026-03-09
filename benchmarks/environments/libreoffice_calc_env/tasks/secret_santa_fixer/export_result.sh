#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Secret Santa Fixer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save the file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Handle potential "Save As" dialog by accepting default location
safe_xdotool ga :1 key Return || true
sleep 1

# Try to export as ODS format for better verification
OUTPUT_FILE="/home/ga/Documents/secret_santa_fixed.ods"

# Open Save As dialog (Ctrl+Shift+S)
echo "Saving as ODS format..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# Confirm any overwrite dialog
safe_xdotool ga :1 key Return || true
sleep 0.5

# Check if files exist
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved as ODS: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif [ -f "/home/ga/Documents/secret_santa.csv" ]; then
    echo "✅ File saved as CSV: /home/ga/Documents/secret_santa.csv"
    ls -lh /home/ga/Documents/secret_santa.csv
elif [ -f "/home/ga/Documents/secret_santa.ods" ]; then
    echo "✅ File saved as ODS: /home/ga/Documents/secret_santa.ods"
    ls -lh /home/ga/Documents/secret_santa.ods
else
    echo "⚠️ Warning: Output file not found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="