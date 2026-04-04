#!/bin/bash
set -euo pipefail

echo "=== Exporting create_placemark task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

# Capture current window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

# Capture screenshot as evidence
scrot /tmp/task_screenshot.png 2>/dev/null || true

# Export the myplaces.kml file content (this contains placemarks)
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    echo "--- myplaces.kml content ---" >> "$RESULT_FILE"
    cat /home/ga/.googleearth/myplaces.kml >> "$RESULT_FILE" 2>/dev/null || true
    echo "" >> "$RESULT_FILE"
    echo "--- myplaces.kml file info ---" >> "$RESULT_FILE"
    ls -la /home/ga/.googleearth/myplaces.kml >> "$RESULT_FILE" 2>/dev/null || true
fi

# Check for backup file modification
if [ -f "/home/ga/.googleearth/myplaces.kml.bak" ]; then
    echo "--- Backup exists (original state) ---" >> "$RESULT_FILE"
    diff /home/ga/.googleearth/myplaces.kml.bak /home/ga/.googleearth/myplaces.kml >> "$RESULT_FILE" 2>/dev/null || echo "Files differ (placemark likely added)" >> "$RESULT_FILE"
fi

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
