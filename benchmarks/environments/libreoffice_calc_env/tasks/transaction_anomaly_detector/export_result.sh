#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Transaction Anomaly Detector Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Wait for file to be saved (check both CSV and ODS formats)
OUTPUT_CSV="/home/ga/Documents/transactions_corrupted.csv"
OUTPUT_ODS="/home/ga/Documents/transactions_corrupted.ods"
OUTPUT_VALIDATED="/home/ga/Documents/validated_transactions.ods"

# Try saving as ODS with specific name
echo "Attempting to save as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Type filename
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/validated_transactions.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Handle any overwrite dialog
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Check which file was saved
if [ -f "$OUTPUT_VALIDATED" ]; then
    echo "✅ File saved: $OUTPUT_VALIDATED"
    ls -lh "$OUTPUT_VALIDATED"
elif [ -f "$OUTPUT_ODS" ]; then
    echo "✅ File saved: $OUTPUT_ODS"
    ls -lh "$OUTPUT_ODS"
elif [ -f "$OUTPUT_CSV" ]; then
    echo "✅ File saved: $OUTPUT_CSV"
    ls -lh "$OUTPUT_CSV"
else
    echo "⚠️ Warning: No output file found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="