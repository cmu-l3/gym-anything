#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Laundry Compliance Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file using Save As dialog to ensure ODS format
echo "Saving file as ODS..."

# Try Ctrl+Shift+S for Save As
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/laundry_compliance_summary.ods"
sleep 0.5

# Press Enter to confirm
safe_xdotool ga :1 key Return
sleep 1

# If dialog appears asking about format, confirm ODS
safe_xdotool ga :1 key Return
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/laundry_compliance_summary.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/laundry_compliance_summary.ods"
    ls -lh /home/ga/Documents/laundry_compliance_summary.ods
else
    echo "⚠️  Warning: File not found at expected location"
    # Try alternative save method (Ctrl+S)
    echo "Attempting fallback save with Ctrl+S..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Check if any of the expected files exist
if [ -f "/home/ga/Documents/laundry_compliance_summary.ods" ]; then
    echo "✅ ODS file confirmed"
elif [ -f "/home/ga/Documents/laundry_bookings.ods" ]; then
    echo "⚠️  Original ODS file exists (may have saved with original name)"
elif [ -f "/home/ga/Documents/laundry_bookings.csv" ]; then
    echo "⚠️  CSV file exists but not saved as ODS"
fi

echo "=== Export Complete ==="