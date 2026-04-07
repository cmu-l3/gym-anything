#!/bin/bash
set -euo pipefail

echo "=== Exporting Gemology Lab Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to force it to flush Preferences, Bookmarks, and History to disk
echo "Closing Chrome to flush SQLite and JSON buffers..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

echo "Data flushed."
echo "=== Export Complete ==="