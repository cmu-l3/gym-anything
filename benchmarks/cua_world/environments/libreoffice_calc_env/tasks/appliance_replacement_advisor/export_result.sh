#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Appliance Replacement Advisor Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+S or Ctrl+Shift+S for Save As)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/appliance_analysis.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If overwrite dialog appears, confirm
safe_xdotool ga :1 key Return
sleep 0.5

# Check if file was saved
if wait_for_file "/home/ga/Documents/appliance_analysis.ods" 5; then
    echo "✅ Analysis saved: /home/ga/Documents/appliance_analysis.ods"
    ls -lh /home/ga/Documents/appliance_analysis.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    # Might still be in CSV format
    if [ -f "/home/ga/Documents/appliance_inventory.csv" ]; then
        echo "📄 CSV file exists (may have been modified)"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# If "Save changes?" dialog appears, save them
safe_xdotool ga :1 key Return || true
sleep 0.5

echo "=== Export Complete ==="