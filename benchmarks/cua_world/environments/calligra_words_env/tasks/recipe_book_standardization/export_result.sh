#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Recipe Book Standardization Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

take_screenshot /tmp/calligra_recipe_book_standardization_post_task.png ga

if [ -f "/home/ga/Documents/recipe_manual_raw.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/recipe_manual_raw.odt || true
else
    echo "Warning: /home/ga/Documents/recipe_manual_raw.odt is missing"
fi

# Attempt graceful quit so it prompts if unsaved, but we don't force save
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

# Provide basic result JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": true,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "=== Export Complete ==="