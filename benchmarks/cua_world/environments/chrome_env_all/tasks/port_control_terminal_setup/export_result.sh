#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Port Control Terminal Setup Result ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences, Bookmarks, Web Data, Local State and History to disk
echo "Closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

echo "=== Export Complete ==="