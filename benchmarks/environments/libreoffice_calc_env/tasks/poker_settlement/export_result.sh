#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Poker Settlement Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file as ODS using Save As dialog
OUTPUT_FILE="/home/ga/Documents/poker_settlement.ods"

echo "Saving as ODS format..."
# Use Ctrl+Shift+S for Save As
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.5
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 1

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 2

# Handle potential overwrite dialog
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Poker settlement saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: ODS file not found, checking CSV..."
    # Fallback: just save the CSV
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    
    if [ -f "/home/ga/Documents/poker_night_data.csv" ]; then
        echo "✅ CSV file saved: /home/ga/Documents/poker_night_data.csv"
    else
        echo "⚠️ Warning: File not found or not recently modified"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="