#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Chemical Reaction Yield Verification Result ==="

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

# Wait for file to be saved (check both possible file names)
RESULT_FILE=""
if wait_for_file "/home/ga/Documents/reaction_data.ods" 5; then
    RESULT_FILE="/home/ga/Documents/reaction_data.ods"
elif wait_for_file "/home/ga/Documents/reaction_data.csv" 3; then
    RESULT_FILE="/home/ga/Documents/reaction_data.csv"
fi

if [ -n "$RESULT_FILE" ]; then
    echo "✅ File saved: $RESULT_FILE"
    ls -lh "$RESULT_FILE"
else
    echo "⚠️ Warning: Result file not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="