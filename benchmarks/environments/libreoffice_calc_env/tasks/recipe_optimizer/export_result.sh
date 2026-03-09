#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Recipe Optimizer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Expected output filename
OUTPUT_FILE="/home/ga/Documents/cookie_analysis.ods"

# Try Save As with specific filename
echo "Saving as cookie_analysis.ods..."
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.8

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# Handle "file exists" dialog if it appears (press Yes to overwrite)
safe_xdotool ga :1 key Return || true
sleep 1

# Check if file was saved
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Fallback: try regular save (Ctrl+S) which saves to same location
    echo "⚠️ Save As may have failed, trying regular save..."
    safe_xdotool ga :1 key ctrl+s
    sleep 2
    
    # Check both possible locations
    if [ -f "$OUTPUT_FILE" ]; then
        echo "✅ File saved: $OUTPUT_FILE"
    elif [ -f "/home/ga/Documents/cookie_experiments.ods" ]; then
        echo "✅ File saved as: /home/ga/Documents/cookie_experiments.ods"
    else
        echo "⚠️ Warning: File not found at expected location"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key ctrl+q
sleep 0.5

echo "=== Export Complete ==="