#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Wallpaper Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save as ODS (Ctrl+Shift+S for Save As)
echo "Saving as ODS format..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.5
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/wallpaper_calculator'
sleep 1

# Press Enter to confirm filename
safe_xdotool ga :1 key Return
sleep 2

# If format dialog appears, press Enter to accept ODS format
safe_xdotool ga :1 key Return
sleep 1

# Check if file was saved
OUTPUT_FILE="/home/ga/Documents/wallpaper_calculator.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: ODS file not found, trying CSV..."
    # Fallback: just save with Ctrl+S (keeps CSV format)
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    if [ -f "/home/ga/Documents/wallpaper_calculator_template.csv" ]; then
        echo "✅ CSV file saved"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="