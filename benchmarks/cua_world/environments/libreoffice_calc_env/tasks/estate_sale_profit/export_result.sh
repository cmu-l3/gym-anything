#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Estate Sale Profit Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file with Ctrl+Shift+S (Save As) to ensure ODS format
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new path
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/estate_sale_results.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key --delay 200 Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/estate_sale_results.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/estate_sale_results.ods"
    ls -lh /home/ga/Documents/estate_sale_results.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/estate_sale_inventory.csv" ]; then
        echo "📄 Original CSV exists (may have been modified)"
    fi
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="