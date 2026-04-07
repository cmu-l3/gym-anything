#!/bin/bash
set -euo pipefail

echo "=== Exporting Digital Archival Workspace Result ==="

# 1. Take final screenshot before closing Chrome
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Record end timestamp
date +%s > /tmp/task_end_time.txt

# 3. Gracefully close Chrome to FLUSH all JSON configurations and SQLite databases to disk
echo "Closing Chrome to flush Preferences, Bookmarks, Web Data, and Local State..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if it's hanging
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Make sure permissions are safe for verifier to read
chmod 644 /home/ga/.config/google-chrome/Default/Bookmarks 2>/dev/null || true
chmod 644 /home/ga/.config/google-chrome/Default/Preferences 2>/dev/null || true
chmod 644 "/home/ga/.config/google-chrome/Local State" 2>/dev/null || true
chmod 644 "/home/ga/.config/google-chrome/Default/Web Data" 2>/dev/null || true

echo "=== Export Complete ==="