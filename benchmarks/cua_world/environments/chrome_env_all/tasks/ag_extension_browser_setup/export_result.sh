#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Agricultural Extension Browser Setup Result ==="

# Record export timestamp
date +%s > /tmp/export_timestamp.txt

# Take final screenshot before closing
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all data (Preferences, Bookmarks, Local State) to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Ensure readable by verifier
chmod -R 755 /home/ga/.config/google-chrome 2>/dev/null || true
chmod 644 /home/ga/.config/google-chrome/Default/Bookmarks 2>/dev/null || true
chmod 644 /home/ga/.config/google-chrome/Default/Preferences 2>/dev/null || true
chmod 644 /home/ga/.config/google-chrome/Local\ State 2>/dev/null || true

echo "=== Export Complete ==="