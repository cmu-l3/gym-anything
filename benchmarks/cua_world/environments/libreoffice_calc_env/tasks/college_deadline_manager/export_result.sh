#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting College Deadline Manager Result ==="

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

# Verify file was saved
if wait_for_file "/home/ga/Documents/college_deadlines.ods" 3; then
    echo "✅ File saved: /home/ga/Documents/college_deadlines.ods"
    ls -lh /home/ga/Documents/college_deadlines.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Wait for process to terminate
for i in {1..5}; do
    if ! pgrep -u ga soffice > /dev/null; then
        echo "✅ LibreOffice closed successfully"
        break
    fi
    sleep 1
done

echo "=== Export Complete ==="