#!/bin/bash
# set -euo pipefail

echo "=== Exporting Appliance Failure Analysis Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Define output file
OUTPUT_FILE="/home/ga/Documents/dishwasher_failure_analysis.ods"

# Save as ODS using Save As dialog
echo "Saving analysis as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Analysis saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found at expected location"
    echo "Attempting regular save..."
    safe_xdotool ga :1 key ctrl+s
    sleep 1
fi

# Close LibreOffice Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="