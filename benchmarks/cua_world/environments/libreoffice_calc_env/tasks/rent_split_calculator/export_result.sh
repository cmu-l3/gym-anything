#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Fair Rent Split Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS format using Save As
echo "Saving file as rent_split_result.ods..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/rent_split_result.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If confirmation dialog appears (file exists), press Enter again
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/rent_split_result.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/rent_split_result.ods"
    ls -lh /home/ga/Documents/rent_split_result.ods
else
    echo "⚠️ Warning: File not found, checking alternative locations..."
    # Also check if CSV was modified
    if [ -f "/home/ga/Documents/rent_split_data.csv" ]; then
        echo "⚠️ Original CSV exists, attempting ODS conversion..."
        ls -lh /home/ga/Documents/rent_split_data.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="