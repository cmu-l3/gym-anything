#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Theater Costume Inventory Update Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name (Ctrl+Shift+S for Save As)
echo "Saving file as costume_inventory_updated.ods..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/costume_inventory_updated.ods'
sleep 0.5

# Press Enter to confirm
safe_xdotool ga :1 key Return
sleep 1.5

# If file format confirmation dialog appears, press Enter again
safe_xdotool ga :1 key Return
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/costume_inventory_updated.ods" 3; then
    echo "✅ File saved: /home/ga/Documents/costume_inventory_updated.ods"
    ls -lh /home/ga/Documents/costume_inventory_updated.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    # Fallback: if saved as CSV, try to find it
    if [ -f "/home/ga/Documents/costume_inventory.csv" ]; then
        echo "   CSV file exists (may have been modified)"
        ls -lh /home/ga/Documents/costume_inventory.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="