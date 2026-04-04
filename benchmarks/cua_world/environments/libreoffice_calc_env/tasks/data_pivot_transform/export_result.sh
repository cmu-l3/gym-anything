#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Data Restructuring Result ==="

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
else
    echo "⚠️  Warning: Could not find Calc window"
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Wait for file to be saved/updated
if wait_for_file "/home/ga/Documents/quarterly_sales.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/quarterly_sales.ods"
    ls -lh /home/ga/Documents/quarterly_sales.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
    # Don't fail, file might still exist
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Verify file exists
if [ -f "/home/ga/Documents/quarterly_sales.ods" ]; then
    echo "✅ Result file exists and ready for verification"
else
    echo "❌ ERROR: Result file not found"
fi

echo "=== Export Complete ==="