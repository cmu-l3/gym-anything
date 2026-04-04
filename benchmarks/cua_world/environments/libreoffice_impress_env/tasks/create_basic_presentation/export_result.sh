#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Basic Presentation Result ==="

# Focus Impress window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/Presentations/basic_presentation.odp" 5; then
    echo "✅ File saved: /home/ga/Documents/Presentations/basic_presentation.odp"
    ls -lh /home/ga/Documents/Presentations/basic_presentation.odp
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Impress (Ctrl+Q)
echo "Closing LibreOffice Impress..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="
