#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting REMS Document Formatting Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot before killing process
take_screenshot /tmp/calligra_rems_document_formatting_post_task.png

if [ -f "/home/ga/Documents/mycophenolate_rems_draft.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/mycophenolate_rems_draft.odt || true
else
    echo "Warning: /home/ga/Documents/mycophenolate_rems_draft.odt is missing"
fi

# We do not forcefully save. The agent must have saved its own changes properly.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="