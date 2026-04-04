#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Genealogy Data Cleanup Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name
echo "Saving cleaned genealogy data..."

# Try Save As to ensure it's saved with the right name
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/genealogy_clean.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key --delay 200 Return || true
sleep 0.5

# Also do a regular save just in case
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/genealogy_clean.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/genealogy_clean.ods"
    ls -lh /home/ga/Documents/genealogy_clean.ods
elif wait_for_file "/home/ga/Documents/family_data_raw.ods" 2; then
    # File might still be named the original
    echo "⚠️ File saved as original name, copying to expected name..."
    sudo -u ga cp /home/ga/Documents/family_data_raw.ods /home/ga/Documents/genealogy_clean.ods
    echo "✅ File available: /home/ga/Documents/genealogy_clean.ods"
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="