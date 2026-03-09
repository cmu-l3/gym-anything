#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Vintage Computer Collection Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name
OUTPUT_FILE="/home/ga/Documents/vintage_computer_collection.ods"

# Use Save As dialog to ensure ODS format
echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear filename field and type new name
echo "Setting output filename..."
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.5
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 1

# Press Enter to save
safe_xdotool ga :1 key --delay 200 Return
sleep 2

# Handle "Confirm file format" dialog if it appears (in case CSV was modified)
# Press Enter again to confirm ODS format
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved successfully: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
    
    # Also check if CSV still exists
    if [ -f "/home/ga/Documents/vintage_computers.csv" ]; then
        echo "📄 Original CSV still present (will try both in verification)"
    fi
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    if [ -f "/home/ga/Documents/vintage_computers.csv" ]; then
        echo "📄 CSV file exists, verifier will attempt to use it"
    else
        echo "❌ No output file found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="