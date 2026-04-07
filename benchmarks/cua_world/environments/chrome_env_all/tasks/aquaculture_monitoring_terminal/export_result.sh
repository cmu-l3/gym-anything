#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Aquaculture Monitoring Terminal Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences, Bookmarks, and Web Data to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# Copy Chrome data explicitly for verifier
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p /tmp/chrome_export
cp "$CHROME_PROFILE/Bookmarks" /tmp/chrome_export/Bookmarks 2>/dev/null || true
cp "$CHROME_PROFILE/Preferences" /tmp/chrome_export/Preferences 2>/dev/null || true
cp "$CHROME_PROFILE/Web Data" "/tmp/chrome_export/Web Data" 2>/dev/null || true
chmod -R 777 /tmp/chrome_export

echo "=== Export Complete ==="