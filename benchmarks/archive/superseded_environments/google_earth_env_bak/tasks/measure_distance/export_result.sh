#!/bin/bash
set -euo pipefail

echo "=== Exporting measure_distance task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

# Capture current window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

# Capture screenshot as evidence of measurement
scrot /tmp/task_screenshot.png 2>/dev/null || true

# Check Google Earth state files for measurement data
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    echo "--- myplaces.kml content ---" >> "$RESULT_FILE"
    cat /home/ga/.googleearth/myplaces.kml >> "$RESULT_FILE" 2>/dev/null || true
fi

# Look for any temporary measurement files
if [ -d "/home/ga/.googleearth" ]; then
    echo "--- Google Earth state files ---" >> "$RESULT_FILE"
    ls -la /home/ga/.googleearth/ >> "$RESULT_FILE" 2>/dev/null || true

    # Check for any KML files that might contain measurements
    find /home/ga/.googleearth -name "*.kml" -exec echo "--- {} ---" \; -exec head -50 {} \; >> "$RESULT_FILE" 2>/dev/null || true
fi

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
