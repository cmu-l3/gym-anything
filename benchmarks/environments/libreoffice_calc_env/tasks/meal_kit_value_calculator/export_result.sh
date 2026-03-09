#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Meal Kit Value Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS using Save As dialog
echo "Saving file as ODS..."

# Try Ctrl+Shift+S for Save As
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/meal_analysis_result.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1.5

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key --delay 200 Return || true
sleep 0.5

# Also try regular save in case Save As failed
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if files were created
if [ -f "/home/ga/Documents/meal_analysis_result.ods" ]; then
    echo "✅ File saved: /home/ga/Documents/meal_analysis_result.ods"
    ls -lh /home/ga/Documents/meal_analysis_result.ods
elif [ -f "/home/ga/Documents/meal_comparison_data.ods" ]; then
    echo "✅ File saved: /home/ga/Documents/meal_comparison_data.ods"
    ls -lh /home/ga/Documents/meal_comparison_data.ods
elif [ -f "/home/ga/Documents/meal_comparison_data.csv" ]; then
    echo "⚠️  CSV file exists (may not have been saved as ODS)"
    ls -lh /home/ga/Documents/meal_comparison_data.csv
else
    echo "⚠️ Warning: Result file not found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="