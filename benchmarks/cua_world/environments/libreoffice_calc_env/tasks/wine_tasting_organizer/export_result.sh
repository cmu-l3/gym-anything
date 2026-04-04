#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Wine Tasting Organizer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Try to save as ODS using Save As dialog
OUTPUT_FILE="/home/ga/Documents/wine_journal_organized.ods"

echo "Saving as ODS file..."
# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# If there's a confirmation dialog (file exists), press Enter again
safe_xdotool ga :1 key Return
sleep 1

# Also try regular save as fallback
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Check if file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE" || true
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/wine_journal.csv" ]; then
        echo "⚠️ CSV file exists but ODS may not have been saved"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="