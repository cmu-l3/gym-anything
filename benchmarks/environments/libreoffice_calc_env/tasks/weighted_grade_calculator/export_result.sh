#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Weighted Grade Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/gradebook.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/gradebook.ods"
    ls -lh /home/ga/Documents/gradebook.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
    # Check if it was saved elsewhere
    if [ -f "/home/ga/Documents/gradebook.csv" ]; then
        echo "📄 CSV file exists: /home/ga/Documents/gradebook.csv"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Double-check that file exists
if [ -f "/home/ga/Documents/gradebook.ods" ]; then
    echo "✅ Final check: gradebook.ods exists"
elif [ -f "/home/ga/Documents/gradebook.csv" ]; then
    echo "⚠️ Warning: Only CSV file exists, ODS not saved"
fi

echo "=== Export Complete ==="