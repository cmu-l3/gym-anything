#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Formula Error Detective Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving repaired spreadsheet..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check if file was saved recently
if wait_for_file "/home/ga/Documents/expense_tracker_broken.ods" 5; then
    echo "✅ File saved: expense_tracker_broken.ods"
    ls -lh /home/ga/Documents/expense_tracker_broken.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Also check if user saved as different name
if [ -f "/home/ga/Documents/expense_tracker_repaired.ods" ]; then
    echo "✅ Also found: expense_tracker_repaired.ods"
    ls -lh /home/ga/Documents/expense_tracker_repaired.ods
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# If dialog appears (unsaved changes), press Escape to cancel
safe_xdotool ga :1 key Escape || true
sleep 0.5

echo "=== Export Complete ==="