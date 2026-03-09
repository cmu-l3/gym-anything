#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Date Format Standardization Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with new name (Save As to ODS format)
echo "Saving file as sales_data_standardized.ods..."

# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/sales_data_standardized.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# Handle potential "file exists" dialog (press Enter to confirm overwrite)
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/sales_data_standardized.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/sales_data_standardized.ods"
    ls -lh /home/ga/Documents/sales_data_standardized.ods
else
    echo "⚠️  Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/sales_data_mixed.csv" ]; then
        echo "📄 CSV file exists (may have been modified in place)"
        ls -lh /home/ga/Documents/sales_data_mixed.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="