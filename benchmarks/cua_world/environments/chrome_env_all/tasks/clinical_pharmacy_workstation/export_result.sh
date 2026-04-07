#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Clinical Pharmacy Workstation Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Bookmarks, Preferences, and Web Data to disk
echo "Closing Chrome to flush SQLite and JSON data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Ensure permissions allow copying
chmod -R 777 /home/ga/.config/google-chrome/Default/ || true

echo "=== Export Complete ==="