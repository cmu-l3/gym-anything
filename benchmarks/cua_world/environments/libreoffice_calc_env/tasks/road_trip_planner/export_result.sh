#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Road Trip Planner Result ==="

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

# Verify file was saved
OUTPUT_FILE="/home/ga/Documents/road_trip_template.ods"
RESULT_FILE="/home/ga/Documents/road_trip_planner_result.ods"

# Copy to result file for clarity
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
    # Copy to result file
    su - ga -c "cp '$OUTPUT_FILE' '$RESULT_FILE'" || true
    echo "✅ Copied to: $RESULT_FILE"
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="