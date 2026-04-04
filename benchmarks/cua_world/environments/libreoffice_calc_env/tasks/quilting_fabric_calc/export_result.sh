#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Quilting Fabric Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with new name as ODS
echo "Saving file as fabric_calculation.ods..."

# Use Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/fabric_calculation.ods"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# If there's a confirmation dialog (file exists), press Enter again
safe_xdotool ga :1 key Return || true
sleep 1

# Also save as CSV for fallback verification
OUTPUT_CSV="/home/ga/Documents/fabric_calculation.csv"
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_CSV"
sleep 0.5
safe_xdotool ga :1 key Return
sleep 2
safe_xdotool ga :1 key Return || true
sleep 1

# Verify files were saved
if wait_for_file "/home/ga/Documents/fabric_calculation.ods" 5; then
    echo "✅ ODS file saved: /home/ga/Documents/fabric_calculation.ods"
    ls -lh /home/ga/Documents/fabric_calculation.ods
else
    echo "⚠️ Warning: ODS file not found or not recently modified"
fi

if [ -f "$OUTPUT_CSV" ]; then
    echo "✅ CSV backup saved: $OUTPUT_CSV"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="