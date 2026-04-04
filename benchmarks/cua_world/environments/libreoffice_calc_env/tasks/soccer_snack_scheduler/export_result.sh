#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Soccer Snack Schedule Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save as ODS (Ctrl+S should work if already named, or use Save As)
echo "Saving file as soccer_snacks_organized.ods..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/soccer_snacks_organized.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If there's a confirmation dialog, press Enter again
safe_xdotool ga :1 key Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "/home/ga/Documents/soccer_snacks_organized.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/soccer_snacks_organized.ods"
    ls -lh /home/ga/Documents/soccer_snacks_organized.ods
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/messy_snack_schedule.csv" ]; then
        echo "ℹ️  Original CSV still exists (may have been modified)"
        ls -lh /home/ga/Documents/messy_snack_schedule.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="