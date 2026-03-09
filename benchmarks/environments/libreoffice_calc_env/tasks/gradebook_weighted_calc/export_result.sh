#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Gradebook Weighted Calculator Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving gradebook..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Verify file was saved
if wait_for_file "/home/ga/Documents/gradebook_template.ods" 5; then
    echo "✅ Gradebook saved: /home/ga/Documents/gradebook_template.ods"
    ls -lh /home/ga/Documents/gradebook_template.ods
else
    echo "⚠️ Warning: Gradebook file not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="