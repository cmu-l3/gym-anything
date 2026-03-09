#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Tool Library Overdue Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for save dialog or confirmation
sleep 1

# If save dialog appears, handle it
# Press Enter to confirm (in case it asks for format confirmation)
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file exists (check both ODS and CSV)
if wait_for_file "/home/ga/Documents/tool_library_data.ods" 3; then
    echo "✅ File saved as: /home/ga/Documents/tool_library_data.ods"
    ls -lh /home/ga/Documents/tool_library_data.ods
elif wait_for_file "/home/ga/Documents/tool_library_data.csv" 2; then
    echo "✅ File saved as: /home/ga/Documents/tool_library_data.csv"
    ls -lh /home/ga/Documents/tool_library_data.csv
else
    echo "⚠️ Warning: Output file not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="