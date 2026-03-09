#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Pool Chemical Balancer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS using Save As dialog
OUTPUT_FILE="/home/ga/Documents/pool_chemical_plan.ods"

echo "Saving as ODS format..."
# Try Save As (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# If there's a confirmation dialog (file exists), press Enter again
safe_xdotool ga :1 key Return
sleep 0.5

# Also try regular save (Ctrl+S) as backup
echo "Performing regular save..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for file to be saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ Pool chemical plan saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
    file "$OUTPUT_FILE"
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    # Check if CSV was modified
    if [ -f "/home/ga/Documents/pool_test_results.csv" ]; then
        echo "📄 CSV file exists (may have been saved in place)"
        ls -lh /home/ga/Documents/pool_test_results.csv
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="
echo ""
echo "Expected output file: $OUTPUT_FILE"
echo "Alternative file: /home/ga/Documents/pool_test_results.csv"