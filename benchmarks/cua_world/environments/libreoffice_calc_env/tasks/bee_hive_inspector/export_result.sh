#!/bin/bash
# set -euo pipefail

echo "=== Exporting Bee Hive Inspector Result ==="

source /workspace/scripts/task_utils.sh

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save as ODS (Ctrl+Shift+S for Save As)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 300 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 80 '/home/ga/Documents/bee_colony_health_analysis.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file exists prompt appears, confirm overwrite
safe_xdotool ga :1 key Return
sleep 0.5

# Verify file was saved
OUTPUT_FILE="/home/ga/Documents/bee_colony_health_analysis.ods"
if wait_for_file "$OUTPUT_FILE" 3; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️  Warning: Expected output file not found, checking alternatives..."
    # Try original CSV location
    if [ -f "/home/ga/Documents/hive_inspections.csv" ]; then
        echo "📄 Found original CSV file"
    fi
    if [ -f "/home/ga/Documents/hive_inspections.ods" ]; then
        echo "📄 Found ODS version of original file"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="