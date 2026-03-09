#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Reading Progress Tracker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save as ODS using Save As dialog
echo "Saving as ODS file..."
OUTPUT_FILE="/home/ga/Documents/reading_challenge_tracker.ods"

# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear filename field and type new name
safe_xdotool ga :1 key ctrl+a
sleep 0.5
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 1

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# Handle "Confirm Format" dialog if it appears (for ODS format)
# Press Enter to confirm ODS format
safe_xdotool ga :1 key Return || true
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️  Warning: ODS file not found, checking for CSV..."
    # Fallback: try to save CSV
    if [ -f "/home/ga/Documents/reading_log.csv" ]; then
        # Try to convert to ODS using command line
        echo "Attempting to save as ODS..."
        safe_xdotool ga :1 key ctrl+s
        sleep 2
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Final check for output files
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Final output: $OUTPUT_FILE"
elif [ -f "/home/ga/Documents/reading_log.ods" ]; then
    echo "✅ Final output: /home/ga/Documents/reading_log.ods"
elif [ -f "/home/ga/Documents/reading_log.csv" ]; then
    echo "⚠️  Output is CSV: /home/ga/Documents/reading_log.csv"
else
    echo "⚠️  Warning: Could not locate output file"
fi

echo "=== Export Complete ==="