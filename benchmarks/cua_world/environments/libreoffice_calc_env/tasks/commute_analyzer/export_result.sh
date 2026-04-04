#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Commute Route Analyzer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name using Save As dialog
OUTPUT_FILE="/home/ga/Documents/commute_analysis.ods"

echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
echo "Setting filename..."
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 1

# Press Enter to save
echo "Saving file..."
safe_xdotool ga :1 key Return
sleep 2

# Handle "file already exists" dialog if it appears
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Analysis saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found at expected location"
    # Try to save with Ctrl+S as fallback
    echo "Attempting fallback save..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
fi

# Close LibreOffice Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Double-check file exists for verification
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Final verification: File exists"
elif [ -f "/home/ga/Documents/commute_data.csv" ]; then
    echo "⚠️ ODS not found, but CSV exists (may have been edited in place)"
fi

echo "=== Export Complete ==="