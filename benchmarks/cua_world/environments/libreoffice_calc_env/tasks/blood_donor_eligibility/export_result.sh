#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Blood Donor Eligibility Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+S or Save As)
echo "Saving file as ODS format..."

# Try regular save first
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Also try Save As to ensure ODS format
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/blood_donor_eligibility.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key Return
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/blood_donor_eligibility.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/blood_donor_eligibility.ods"
    ls -lh /home/ga/Documents/blood_donor_eligibility.ods || true
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/blood_donors.csv" ]; then
        echo "   CSV file exists (may have been modified in place)"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="