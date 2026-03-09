#!/bin/bash
# set -euo pipefail

echo "=== Exporting Appliance Warranty Tracker Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

OUTPUT_FILE="/home/ga/Documents/warranty_tracker.ods"

# Save As dialog (Ctrl+Shift+S)
echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Return to save
safe_xdotool ga :1 key Return
sleep 2

# If file exists dialog appears, press Return to overwrite
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Warranty tracker saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found at expected location"
    # Try to find it in case it was saved elsewhere
    find /home/ga/Documents -name "*.ods" -mmin -1 2>/dev/null | head -5 || true
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="