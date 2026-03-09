#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Golden Hour Schedule Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+S will save as ODS after opening CSV)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# If prompted for format, confirm ODS
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved (check both possible locations)
OUTPUT_FILE="/home/ga/Documents/photo_locations.ods"
CSV_FILE="/home/ga/Documents/photo_locations.csv"

if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Schedule saved as ODS: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
elif [ -f "$CSV_FILE" ]; then
    echo "⚠️  File saved as CSV (not ODS)"
    ls -lh "$CSV_FILE"
else
    echo "⚠️  Warning: Output file not found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# If unsaved changes dialog appears, don't save again
safe_xdotool ga :1 key Escape || true

echo "=== Export Complete ==="