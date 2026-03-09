#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Legacy POS Rescue Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Try to save the file with a specific name
OUTPUT_FILE="/home/ga/Documents/cleaned_customer_data.csv"

# Save As dialog (Ctrl+Shift+S)
echo "Opening Save As dialog..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file format dialog appears, confirm CSV format
safe_xdotool ga :1 key Return
sleep 1

# Check if file was created
if wait_for_file "$OUTPUT_FILE" 3; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: Cleaned file not found, checking for alternatives..."
    
    # Check if original was modified
    if [ -f "/home/ga/Documents/old_pos_export.csv" ]; then
        echo "⚠️ Original CSV still exists"
    fi
    
    # Try regular save in case file was already named
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Handle "Save changes?" dialog if it appears
safe_xdotool ga :1 key Return || true
sleep 0.5

echo "=== Export Complete ==="