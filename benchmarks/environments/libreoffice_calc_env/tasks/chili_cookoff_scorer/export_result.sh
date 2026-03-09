#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Chili Cook-Off Scorer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS using Save As dialog
echo "Saving file as ODS..."

# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/chili_cookoff_result.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# If overwrite dialog appears, confirm
safe_xdotool ga :1 key Return || true
sleep 0.5

# Alternative: try simple Ctrl+S save
if [ ! -f "/home/ga/Documents/chili_cookoff_result.ods" ]; then
    echo "Trying alternative save method..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1.5
fi

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/chili_cookoff_result.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/chili_cookoff_result.ods"
    ls -lh /home/ga/Documents/chili_cookoff_result.ods
else
    # Check if CSV was modified instead
    if [ -f "/home/ga/Documents/chili_scores_raw.csv" ]; then
        echo "⚠️ ODS not found, checking CSV..."
        ls -lh /home/ga/Documents/chili_scores_raw.csv
    else
        echo "⚠️ Warning: Result file not found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="