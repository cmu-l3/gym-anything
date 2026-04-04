#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Sleep Pattern Optimizer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS format
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/sleep_analysis.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# Handle "overwrite" dialog if it appears
safe_xdotool ga :1 key Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/sleep_analysis.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/sleep_analysis.ods"
    ls -lh /home/ga/Documents/sleep_analysis.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/sleep_log.csv" ]; then
        # Try to save as ODS with different approach
        safe_xdotool ga :1 key --delay 200 ctrl+s
        sleep 1
        echo "✅ CSV file updated: /home/ga/Documents/sleep_log.csv"
    else
        echo "⚠️ Warning: File may not have been saved"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="