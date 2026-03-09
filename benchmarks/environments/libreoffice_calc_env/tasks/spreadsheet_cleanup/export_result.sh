#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Spreadsheet Cleanup Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Also try Save As to ensure we get the cleaned version
echo "Attempting Save As..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1.5

# Type the output filename
OUTPUT_FILE="/home/ga/Documents/event_registrations_clean.ods"
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file exists dialog appears (overwrite), press Enter again
safe_xdotool ga :1 key Return
sleep 0.5

# Check if file was saved
if wait_for_file "$OUTPUT_FILE" 3; then
    echo "✅ Cleaned file saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Fallback: check if messy file was modified in place
    if wait_for_file "/home/ga/Documents/event_registrations_messy.ods" 1; then
        echo "⚠️  Messy file may have been modified in place"
        ls -lh /home/ga/Documents/event_registrations_messy.ods
    else
        echo "⚠️  Warning: Could not confirm file save"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="