#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Auction Analysis Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name (Ctrl+Shift+S for Save As)
echo "Saving as auction_analysis.ods..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/auction_analysis.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key Return || true
sleep 1

# Also do a regular save (Ctrl+S) as fallback
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for file to be saved
OUTPUT_FILE="/home/ga/Documents/auction_analysis.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Check if original CSV was modified
    if wait_for_file "/home/ga/Documents/auction_data.csv" 5; then
        echo "⚠️ Warning: auction_analysis.ods not found, but auction_data.csv exists"
        ls -lh /home/ga/Documents/auction_data.csv
    else
        echo "⚠️ Warning: Output file not found or not recently modified"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="