#!/bin/bash
set -euo pipefail

echo "=== Exporting Multilingual Counter Setup Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract Web Data for SQLite checks before closing (can be locked, but safer to copy)
cp "/home/ga/.config/google-chrome/Default/Web Data" "/tmp/Web_Data_Export" 2>/dev/null || true
chmod 666 "/tmp/Web_Data_Export" 2>/dev/null || true

# Gracefully close Chrome to flush Preferences and Bookmarks to disk
echo "Closing Chrome to flush data..."
pkill -f "chrome" 2>/dev/null || true
sleep 3

# Force kill if still lingering
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

echo "=== Export Complete ==="