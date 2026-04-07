#!/bin/bash
echo "=== Exporting result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close Chrome to forcibly flush all Settings/Bookmarks/Web Data changes to disk
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

echo "=== Export Complete ==="