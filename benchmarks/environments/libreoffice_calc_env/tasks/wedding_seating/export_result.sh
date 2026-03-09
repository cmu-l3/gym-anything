#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Wedding Seating Arrangement Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+S should work if already ODS, otherwise use Save As)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Try to ensure it's saved as ODS format
OUTPUT_FILE="/home/ga/Documents/wedding_seating.ods"

# If original was CSV, do explicit Save As
if [ ! -f "/home/ga/Documents/wedding_guest_list.ods" ]; then
    echo "Original was CSV, doing Save As to ODS..."
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
    
    # If format dialog appears, confirm ODS
    safe_xdotool ga :1 key --delay 200 Return
    sleep 0.5
fi

# Check if file exists (try multiple possible names)
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif [ -f "/home/ga/Documents/wedding_guest_list.ods" ]; then
    echo "✅ File saved: /home/ga/Documents/wedding_guest_list.ods"
    ls -lh "/home/ga/Documents/wedding_guest_list.ods"
elif [ -f "/home/ga/Documents/wedding_guest_list.csv" ]; then
    echo "⚠️ File saved as CSV: /home/ga/Documents/wedding_guest_list.csv"
    ls -lh "/home/ga/Documents/wedding_guest_list.csv"
else
    echo "⚠️ Warning: Could not confirm file save"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# If unsaved changes dialog appears, choose Don't Save
safe_xdotool ga :1 key --delay 100 Tab Return
sleep 0.3

echo "=== Export Complete ==="