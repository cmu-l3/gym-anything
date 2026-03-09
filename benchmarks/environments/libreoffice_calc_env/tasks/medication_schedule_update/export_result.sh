#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Medication Schedule Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS format (Save As)
echo "Saving as ODS format..."
OUTPUT_FILE="/home/ga/Documents/medication_schedule_updated.ods"

# Use Save As dialog
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 1.5

# Handle any "confirm overwrite" dialog if it appears
safe_xdotool ga :1 key --delay 200 Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    
    # Try saving CSV as fallback
    CSV_FILE="/home/ga/Documents/medication_schedule.csv"
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    
    if [ -f "$CSV_FILE" ]; then
        echo "✅ CSV file exists: $CSV_FILE"
    else
        echo "⚠️ Warning: File save may have failed"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="