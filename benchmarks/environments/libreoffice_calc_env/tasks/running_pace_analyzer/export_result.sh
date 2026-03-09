#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Running Pace Analyzer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file as ODS (Ctrl+Shift+S for Save As)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/running_analysis.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# If there's a confirmation dialog about file format, press Enter again
safe_xdotool ga :1 key --delay 200 Return
sleep 0.5

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/running_analysis.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/running_analysis.ods"
    ls -lh /home/ga/Documents/running_analysis.ods || true
else
    # Try alternate save method (Ctrl+S on original file)
    echo "⚠️ Trying alternate save method..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="