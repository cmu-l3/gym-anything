#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Insurance Inventory Cleanup Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check if file was saved with new name, otherwise use original
OUTPUT_FILE="/home/ga/Documents/home_inventory_cleaned.ods"
ORIGINAL_FILE="/home/ga/Documents/home_inventory_messy.ods"

# If agent saved with different name, try to detect it
if [ ! -f "$OUTPUT_FILE" ]; then
    # Check if original file was modified
    if [ -f "$ORIGINAL_FILE" ]; then
        echo "Using original file (may have been edited in place)"
        OUTPUT_FILE="$ORIGINAL_FILE"
    fi
fi

# Verify file exists and was recently modified
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found or not recently modified"
    echo "Checking for any ODS files in Documents..."
    ls -lht /home/ga/Documents/*.ods 2>/dev/null || echo "No ODS files found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Handle "Save changes?" dialog if it appears
safe_xdotool ga :1 key --delay 200 Return 2>/dev/null || true
sleep 0.5

echo "=== Export Complete ==="