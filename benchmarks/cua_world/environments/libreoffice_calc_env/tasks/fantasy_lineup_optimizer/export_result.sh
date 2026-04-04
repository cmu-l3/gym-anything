#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Fantasy Football Lineup Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save as ODS format (Ctrl+Shift+S for Save As)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.5
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/fantasy_lineup.ods'
sleep 1

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Handle any overwrite confirmation if file exists
safe_xdotool ga :1 key --delay 200 Return || true
sleep 1

# Verify file was saved
if wait_for_file "/home/ga/Documents/fantasy_lineup.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/fantasy_lineup.ods"
    ls -lh /home/ga/Documents/fantasy_lineup.ods
else
    echo "⚠️ Warning: File not found, trying to save with Ctrl+S"
    # Fallback: try regular save
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
    
    # Check both possible locations
    if [ -f "/home/ga/Documents/fantasy_lineup.ods" ]; then
        echo "✅ File saved via Ctrl+S"
    elif [ -f "/home/ga/Documents/roster_week7.csv" ]; then
        echo "⚠️ File may still be in CSV format"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="