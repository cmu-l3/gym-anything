#!/bin/bash
set -e
echo "=== Exporting assistive_browser_setup result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Record end time
date +%s > /tmp/task_end_time.txt

# Gracefully close Chrome to flush all Preferences/Bookmarks data to disk
echo "Closing Chrome to flush data..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Check if desktop shortcut was created
SHORTCUT_CREATED="false"
if [ -f "/home/ga/Desktop/Accessible_Chrome.desktop" ]; then
    SHORTCUT_CREATED="true"
fi

# Export short summary JSON for debugging
cat > /tmp/task_result.json << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(cat /tmp/task_end_time.txt 2>/dev/null || echo 0),
    "shortcut_created": $SHORTCUT_CREATED
}
EOF

echo "=== Export Complete ==="