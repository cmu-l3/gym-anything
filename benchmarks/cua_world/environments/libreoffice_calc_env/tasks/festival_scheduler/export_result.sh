#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Festival Scheduler Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Define output file path
OUTPUT_FILE="/home/ga/Documents/festival_schedule.ods"

# Save as ODS using Save As dialog
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to confirm
safe_xdotool ga :1 key Return
sleep 1.5

# If there's a confirmation dialog (file exists), press Enter again
safe_xdotool ga :1 key Return
sleep 0.5

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Festival schedule saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: Output file not found at expected location"
    # Try alternative save method
    echo "Attempting alternative save (Ctrl+S)..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="