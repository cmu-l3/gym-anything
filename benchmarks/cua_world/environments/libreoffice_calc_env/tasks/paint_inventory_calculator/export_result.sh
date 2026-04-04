#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Paint Inventory Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save as ODS using Save As dialog
echo "Saving as ODS file..."

# Try Ctrl+Shift+S for Save As
safe_xdotool ga :1 key --delay 300 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/paint_calculation.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# If there's a confirmation dialog (file exists), press Enter again
safe_xdotool ga :1 key Return
sleep 0.5

# Also try regular save (Ctrl+S) as backup
echo "Performing backup save..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if file was created
OUTPUT_FILE="/home/ga/Documents/paint_calculation.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ ODS not found, checking for CSV..."
    if [ -f "/home/ga/Documents/paint_rooms.csv" ]; then
        echo "✅ CSV file exists (may have been modified)"
        ls -lh /home/ga/Documents/paint_rooms.csv
    else
        echo "❌ Warning: No output files found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="