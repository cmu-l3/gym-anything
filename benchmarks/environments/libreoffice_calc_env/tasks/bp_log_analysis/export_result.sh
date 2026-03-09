#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Blood Pressure Log Analysis Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save the file as ODS (Save As dialog)
echo "Saving analysis as ODS..."
safe_xdotool ga :1 key --delay 300 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/bp_analysis_complete.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1.5

# Handle potential "file exists" dialog by pressing Enter again
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/bp_analysis_complete.ods" 5; then
    echo "✅ Analysis saved: /home/ga/Documents/bp_analysis_complete.ods"
    ls -lh /home/ga/Documents/bp_analysis_complete.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    # Fallback: try saving current CSV
    if [ -f "/home/ga/Documents/bp_readings_3weeks.csv" ]; then
        echo "CSV file exists, may have been updated"
    fi
fi

# Close LibreOffice Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Handle potential "save changes" dialog
safe_xdotool ga :1 key --delay 200 Return
sleep 0.3

echo "=== Export Complete ==="