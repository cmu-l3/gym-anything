#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Meal Train Organizer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file using Save As dialog to ensure ODS format
echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
echo "Entering filename..."
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/meal_train_resolved.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# If file already exists, confirm overwrite
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved
OUTPUT_FILE="/home/ga/Documents/meal_train_resolved.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Meal train spreadsheet saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: Resolved file not found, trying alternative save..."
    # Try regular save as backup
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="