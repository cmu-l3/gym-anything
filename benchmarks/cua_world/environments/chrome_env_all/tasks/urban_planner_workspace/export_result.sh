#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Municipal Urban Planner Task Result ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences, Bookmarks, and SQLite buffers to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Make sure permissions are safe for verifier
chmod -R 755 /home/ga/.config/google-chrome/Default || true

echo "=== Export Complete ==="