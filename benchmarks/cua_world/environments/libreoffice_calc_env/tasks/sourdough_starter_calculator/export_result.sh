#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Sourdough Starter Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Ensure we're saving as ODS format
# Use Save As to ensure ODS format
echo "Saving file as ODS..."
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/sourdough_analysis.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# Handle "confirm overwrite" dialog if it appears
safe_xdotool ga :1 key Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/sourdough_analysis.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/sourdough_analysis.ods"
    ls -lh /home/ga/Documents/sourdough_analysis.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV fallback..."
    if [ -f "/home/ga/Documents/feeding_log.csv" ]; then
        echo "⚠️ CSV file exists, will try to verify from CSV"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="