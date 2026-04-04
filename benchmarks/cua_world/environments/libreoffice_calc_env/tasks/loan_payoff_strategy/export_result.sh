#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Loan Payoff Strategy Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+S will save in current format, but we'll also try Save As)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1.5

# Wait for file to be saved (check both CSV and ODS versions)
OUTPUT_ODS="/home/ga/Documents/loan_strategy.ods"
OUTPUT_CSV="/home/ga/Documents/my_loans.csv"

if wait_for_file "$OUTPUT_CSV" 3; then
    echo "✅ File saved (CSV format): $OUTPUT_CSV"
    ls -lh "$OUTPUT_CSV"
fi

# Try to also save as ODS explicitly for better verification
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1

# Type filename
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_ODS"
sleep 0.5

# Press Return to save
safe_xdotool ga :1 key Return
sleep 1

# Handle any overwrite dialog if present
safe_xdotool ga :1 key Return
sleep 0.5

if [ -f "$OUTPUT_ODS" ]; then
    echo "✅ File saved (ODS format): $OUTPUT_ODS"
    ls -lh "$OUTPUT_ODS"
elif [ -f "$OUTPUT_CSV" ]; then
    echo "⚠️ CSV file exists, ODS may not have been created"
else
    echo "⚠️ Warning: Neither file found after save attempt"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="