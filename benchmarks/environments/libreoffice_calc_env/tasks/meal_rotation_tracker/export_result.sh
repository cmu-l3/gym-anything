#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Meal Rotation Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with a specific name (Save As)
OUTPUT_FILE="/home/ga/Documents/meal_rotation_analysis.ods"

echo "Saving as ODS format..."
# Use Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If file exists dialog appears (overwrite), press Enter again
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Also save the regular way (Ctrl+S) as backup
echo "Saving file (Ctrl+S)..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE" || true
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/meal_log.csv" ]; then
        echo "📄 CSV file exists (original)"
    fi
    if [ -f "/home/ga/Documents/meal_log.ods" ]; then
        echo "📄 ODS file exists (alternate location)"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="