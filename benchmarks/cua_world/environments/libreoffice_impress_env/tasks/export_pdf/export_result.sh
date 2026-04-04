#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting PDF Result ==="

# The PDF should have been created by the agent
# We just need to close Impress

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key --delay 200 ctrl+q
fi

# Check for PDF
if [ -f "/home/ga/Documents/Presentations/export_test.pdf" ]; then
    echo "✅ PDF found: export_test.pdf"
    ls -lh /home/ga/Documents/Presentations/export_test.pdf
else
    echo "⚠️ PDF not found at expected location"
fi

echo "=== Export Complete ==="
