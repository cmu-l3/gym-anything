#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Medication Refill Coordinator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with a specific name as ODS
echo "Saving file as medication_refill_schedule.ods..."

# Use Save As to ensure ODS format
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/medication_refill_schedule.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# Handle any "file exists" dialog by pressing Enter again
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/medication_refill_schedule.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/medication_refill_schedule.ods"
    ls -lh /home/ga/Documents/medication_refill_schedule.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/medications.csv" ]; then
        echo "✅ CSV file exists (may have been modified)"
        ls -lh /home/ga/Documents/medications.csv
    else
        echo "⚠️ Warning: No output file found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="