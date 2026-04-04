#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Tool Lending Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS using Save As dialog
# First try Ctrl+S for simple save
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# If file needs format conversion, handle the dialog
# The CSV might prompt to save as ODS
safe_xdotool ga :1 key --delay 100 Return || true
sleep 1

# Ensure file is saved as ODS by using Save As
echo "Ensuring ODS format..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/tool_lending_result.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1.5

# Handle "Confirm" dialog if file exists
safe_xdotool ga :1 key --delay 100 Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/tool_lending_result.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/tool_lending_result.ods"
    ls -lh /home/ga/Documents/tool_lending_result.ods
elif [ -f "/home/ga/Documents/tool_lending.ods" ]; then
    echo "✅ File saved as: /home/ga/Documents/tool_lending.ods"
    ls -lh /home/ga/Documents/tool_lending.ods
elif [ -f "/home/ga/Documents/tool_lending.csv" ]; then
    echo "⚠️ File exists as CSV: /home/ga/Documents/tool_lending.csv"
    ls -lh /home/ga/Documents/tool_lending.csv
else
    echo "⚠️ Warning: Result file not found"
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="