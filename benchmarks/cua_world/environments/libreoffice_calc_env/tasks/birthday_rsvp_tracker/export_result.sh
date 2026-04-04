#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Birthday RSVP Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Save as with specific name to ensure it's captured
echo "Saving as birthday_rsvp_final.ods..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/birthday_rsvp_final.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/birthday_rsvp_final.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/birthday_rsvp_final.ods"
    ls -lh /home/ga/Documents/birthday_rsvp_final.ods
else
    echo "⚠️ Warning: birthday_rsvp_final.ods not found"
    # Check if original file was modified
    if [ -f "/home/ga/Documents/birthday_rsvp.ods" ]; then
        echo "📄 Original file exists: /home/ga/Documents/birthday_rsvp.ods"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="