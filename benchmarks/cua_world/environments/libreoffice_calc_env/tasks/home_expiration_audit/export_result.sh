#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Home Expiration Audit Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Try to save as ODS with specific filename
OUTPUT_FILE="/home/ga/Documents/home_expiration_audit_cleaned.ods"

echo "Attempting to save as ODS..."

# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# Handle potential overwrite dialog
safe_xdotool ga :1 key Return
sleep 0.5

# Also try regular save (Ctrl+S) in case file was already named
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if file was created
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif [ -f "/home/ga/Documents/home_inventory_messy.ods" ]; then
    echo "⚠️ File saved as: home_inventory_messy.ods"
    ls -lh "/home/ga/Documents/home_inventory_messy.ods"
else
    echo "⚠️ Warning: Output file not found at expected location"
    echo "Checking Documents directory:"
    ls -lh /home/ga/Documents/ || true
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="