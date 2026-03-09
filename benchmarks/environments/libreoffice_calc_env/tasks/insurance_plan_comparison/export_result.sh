#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Insurance Plan Comparison Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Save As to ensure ODS format)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/insurance_comparison.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# If prompted about overwriting or format, confirm
safe_xdotool ga :1 key Return
sleep 0.5

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/insurance_comparison.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/insurance_comparison.ods"
    ls -lh /home/ga/Documents/insurance_comparison.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/insurance_plans_template.csv" ]; then
        echo "📄 CSV file exists, attempting to copy as fallback"
        sudo -u ga cp /home/ga/Documents/insurance_plans_template.csv /home/ga/Documents/insurance_comparison.csv || true
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="