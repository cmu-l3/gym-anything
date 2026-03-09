#!/bin/bash
# set -euo pipefail

echo "=== Exporting Solar Panel Analysis Result ==="

source /workspace/scripts/task_utils.sh

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

# Wait for file to be saved/updated
OUTPUT_FILE="/home/ga/Documents/solar_production_log.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    # Try CSV format
    OUTPUT_FILE="/home/ga/Documents/solar_production_log.csv"
    if wait_for_file "$OUTPUT_FILE" 3; then
        echo "✅ File saved: $OUTPUT_FILE"
        ls -lh "$OUTPUT_FILE"
    else
        echo "⚠️ Warning: File not found or not recently modified"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="