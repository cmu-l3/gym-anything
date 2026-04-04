#!/bin/bash
# set -euo pipefail

echo "=== Exporting Plant Watering Schedule Result ==="

source /workspace/scripts/task_utils.sh

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with Ctrl+S
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Wait for save dialog or file update
# Check if the expected file exists and was recently modified
OUTPUT_FILE="/home/ga/Documents/plant_schedule.ods"
FALLBACK_CSV="/home/ga/Documents/plants_data.csv"
FALLBACK_ODS="/home/ga/Documents/plants_data.ods"

if wait_for_file "$OUTPUT_FILE" 3; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif wait_for_file "$FALLBACK_ODS" 3; then
    echo "✅ File saved as: $FALLBACK_ODS"
    ls -lh "$FALLBACK_ODS"
elif [ -f "$FALLBACK_CSV" ]; then
    echo "⚠️  Warning: Only CSV found, ODS may not have been saved"
    ls -lh "$FALLBACK_CSV"
else
    echo "⚠️  Warning: Output file not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Give it extra time to close cleanly
sleep 1

echo "=== Export Complete ==="