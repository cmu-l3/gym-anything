#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Geocache Route Optimizer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Define output file
OUTPUT_FILE="/home/ga/Documents/geocache_route_plan.ods"

# Save file using Ctrl+Shift+S (Save As) to ensure ODS format
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 100 Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key --delay 100 Return
sleep 1

# Wait for file to be saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found at expected location"
    # Try alternate location (might have been saved as CSV)
    if [ -f "/home/ga/Documents/geocache_data.csv" ]; then
        echo "📄 Original CSV file exists: /home/ga/Documents/geocache_data.csv"
    fi
    if [ -f "/home/ga/Documents/geocache_data.ods" ]; then
        echo "📄 Auto-converted ODS exists: /home/ga/Documents/geocache_data.ods"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="