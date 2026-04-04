#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Library Due Date Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Try to save as ODS with specific filename
echo "Saving file as library_organized.ods..."

# Use Save As dialog
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/library_organized.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If format confirmation dialog appears, press Enter again
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/library_organized.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/library_organized.ods"
    ls -lh /home/ga/Documents/library_organized.ods || true
else
    echo "⚠️ Primary save location not found, checking alternatives..."
    # Also check if original CSV was saved
    if [ -f "/home/ga/Documents/library_checkouts.ods" ]; then
        echo "✅ Alternative file found: library_checkouts.ods"
        ls -lh /home/ga/Documents/library_checkouts.ods || true
    else
        echo "⚠️ Warning: Expected file not found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="