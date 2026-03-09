#!/bin/bash
# set -euo pipefail

echo "=== Exporting Practice Log Analyzer Result ==="

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
sleep 2

# If CSV import dialog appears, confirm save as ODS
safe_xdotool ga :1 key --delay 200 Return || true
sleep 1

# Wait for file to be saved (check for ODS version)
OUTPUT_FILE="/home/ga/Documents/practice_log.ods"
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved as ODS: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif [ -f "/home/ga/Documents/practice_log.csv" ]; then
    echo "⚠️ Warning: File may still be CSV format"
    ls -lh /home/ga/Documents/practice_log.csv
else
    echo "⚠️ Warning: Output file not found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# If unsaved changes dialog appears, save them
safe_xdotool ga :1 key --delay 200 Return || true
sleep 0.5

echo "=== Export Complete ==="