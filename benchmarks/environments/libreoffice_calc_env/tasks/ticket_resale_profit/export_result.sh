#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Ticket Resale Profit Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Ensure we're on the main data sheet (first sheet)
safe_xdotool ga :1 key ctrl+Page_Up ctrl+Page_Up
sleep 0.3

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check if file exists and was recently modified
EXPECTED_FILE="/home/ga/Documents/ticket_resale_data.csv"
ODS_FILE="/home/ga/Documents/ticket_resale_data.ods"

if [ -f "$ODS_FILE" ]; then
    echo "✅ ODS file saved: $ODS_FILE"
    ls -lh "$ODS_FILE"
elif [ -f "$EXPECTED_FILE" ]; then
    echo "✅ CSV file saved: $EXPECTED_FILE"
    ls -lh "$EXPECTED_FILE"
else
    echo "⚠️ Warning: Expected output file not found"
    ls -lh /home/ga/Documents/ || true
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="