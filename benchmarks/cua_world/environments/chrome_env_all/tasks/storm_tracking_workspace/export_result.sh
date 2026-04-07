#!/bin/bash
# Export script for storm_tracking_workspace task
set -euo pipefail

echo "=== Exporting Storm Tracking Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all data (Bookmarks, Preferences, Web Data) to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Make copies of important Chrome files to /tmp so verifier can easily grab them
cp -f /home/ga/.config/google-chrome/Default/Bookmarks /tmp/Bookmarks_export.json 2>/dev/null || true
cp -f /home/ga/.config/google-chrome/Default/Preferences /tmp/Preferences_export.json 2>/dev/null || true
cp -f /home/ga/.config/google-chrome/Default/Web\ Data /tmp/WebData_export.sqlite 2>/dev/null || true

chmod 644 /tmp/Bookmarks_export.json /tmp/Preferences_export.json /tmp/WebData_export.sqlite 2>/dev/null || true

echo "=== Export Complete ==="