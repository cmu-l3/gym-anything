#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Professional Certification Renewal Manager Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✅ Calc window focused"
else
    echo "⚠️  Could not focus Calc window, attempting alternative..."
    su - ga -c "DISPLAY=:1 wmctrl -a 'LibreOffice Calc'" || true
fi

sleep 0.5

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/certification_tracker.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/certification_tracker.ods"
    ls -lh /home/ga/Documents/certification_tracker.ods || true
else
    echo "⚠️  Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Verify file exists
if [ -f "/home/ga/Documents/certification_tracker.ods" ]; then
    echo "✅ Export successful: certification_tracker.ods"
    ls -lh /home/ga/Documents/certification_tracker.ods
else
    echo "❌ Export may have failed - file not found"
fi

echo "=== Export Complete ==="