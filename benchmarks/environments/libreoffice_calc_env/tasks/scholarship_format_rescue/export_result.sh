#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Scholarship Format Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save current work first (Ctrl+S)
echo "Saving current work..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Now Save As to ensure CSV export
echo "Exporting as CSV..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type the required filename
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3

# Type the exact required filename
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/financial_data_submission.csv'
sleep 0.5

# Press Enter to confirm filename
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Handle "Confirm File Format" dialog if it appears
# Press Enter to confirm using CSV format
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Check if file was created
EXPECTED_FILE="/home/ga/Documents/financial_data_submission.csv"
if wait_for_file "$EXPECTED_FILE" 3; then
    echo "✅ File exported: $EXPECTED_FILE"
    ls -lh "$EXPECTED_FILE"
    echo "File size: $(stat -f%z "$EXPECTED_FILE" 2>/dev/null || stat -c%s "$EXPECTED_FILE" 2>/dev/null) bytes"
else
    echo "⚠️ Warning: Expected file not found at $EXPECTED_FILE"
    echo "Checking for alternative locations..."
    find /home/ga/Documents -name "*.csv" -type f -mmin -2 2>/dev/null || true
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# If close dialog appears (unsaved changes), don't save again
safe_xdotool ga :1 key --delay 100 Tab Return 2>/dev/null || true
sleep 0.3

echo "=== Export Complete ==="