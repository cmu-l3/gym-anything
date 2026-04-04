#!/bin/bash
set -euo pipefail

echo "=== Exporting navigate_to_location task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

# Capture current window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

# Capture screenshot as evidence
scrot /tmp/task_screenshot.png 2>/dev/null || true

# Check Google Earth state files
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    echo "--- myplaces.kml content ---" >> "$RESULT_FILE"
    head -100 /home/ga/.googleearth/myplaces.kml >> "$RESULT_FILE" 2>/dev/null || true
fi

# List recent cache activity
if [ -d "/home/ga/.googleearth/Cache" ]; then
    echo "--- Recent cache files ---" >> "$RESULT_FILE"
    ls -lt /home/ga/.googleearth/Cache 2>/dev/null | head -10 >> "$RESULT_FILE" || true
fi

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
