#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Oral History Archive Validator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+Shift+S for Save As, or Ctrl+S if already ODS)
echo "Saving file..."

# First try regular save (Ctrl+S)
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# If it's still CSV, it should have been saved. If Save As dialog appeared, handle it
# Try to save as ODS explicitly
OUTPUT_FILE="/home/ga/Documents/oral_history_cleaned.ods"

# Use Save As to ensure ODS format
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Confirm overwrite if asked
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Check if file was saved
if wait_for_file "/home/ga/Documents/oral_history_cleaned.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/oral_history_cleaned.ods"
    ls -lh /home/ga/Documents/oral_history_cleaned.ods
elif wait_for_file "/home/ga/Documents/oral_history_interviews.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/oral_history_interviews.ods"
    ls -lh /home/ga/Documents/oral_history_interviews.ods
else
    echo "⚠️ Warning: ODS file may not have been saved"
    ls -lh /home/ga/Documents/ | grep -i oral || true
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="