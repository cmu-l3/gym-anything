#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Tip Pool Calculator Result ==="

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

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/tip_pool.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/tip_pool.ods"
    ls -lh /home/ga/Documents/tip_pool.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Verify file exists
if [ -f "/home/ga/Documents/tip_pool.ods" ]; then
    echo "✅ Export complete"
    file_size=$(stat -f%z "/home/ga/Documents/tip_pool.ods" 2>/dev/null || stat -c%s "/home/ga/Documents/tip_pool.ods" 2>/dev/null)
    echo "📊 File size: $file_size bytes"
else
    echo "⚠️ Export verification: file may not exist"
fi

echo "=== Export Complete ==="