#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Bank Import Formatter Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Try to save the file - user should have already saved as CSV
# But we'll trigger a save just in case
echo "Triggering save..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check if CSV was created
if [ -f "/home/ga/Documents/transactions_formatted.csv" ]; then
    echo "✅ Found transactions_formatted.csv"
    ls -lh /home/ga/Documents/transactions_formatted.csv
elif [ -f "/home/ga/Documents/bank_export_messy.csv" ]; then
    echo "⚠️  Found bank_export_messy.csv (possibly saved as CSV)"
    ls -lh /home/ga/Documents/bank_export_messy.csv
elif [ -f "/home/ga/Documents/bank_export_messy.ods" ]; then
    echo "⚠️  Found bank_export_messy.ods (not exported as CSV)"
    ls -lh /home/ga/Documents/bank_export_messy.ods
else
    echo "⚠️  No output file found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Close any text editors that might be open
pkill -f "format_requirements.txt" || true

echo "=== Export Complete ==="