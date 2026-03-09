#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Theater Revenue Decoder Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save with new name using Save As dialog
echo "Opening Save As dialog..."
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
echo "Setting filename..."
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/GalaTicketRevenue_Documented.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# Handle any "file exists" dialog by pressing Enter again
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/GalaTicketRevenue_Documented.ods" 5; then
    echo "✅ Documented spreadsheet saved: GalaTicketRevenue_Documented.ods"
    ls -lh /home/ga/Documents/GalaTicketRevenue_Documented.ods
else
    echo "⚠️ Warning: Documented file not found"
    # Try to save original file as backup
    safe_xdotool ga :1 key ctrl+s
    sleep 1
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key ctrl+q
sleep 0.5

echo "=== Export Complete ==="