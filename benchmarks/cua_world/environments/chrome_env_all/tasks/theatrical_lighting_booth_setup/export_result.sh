#!/bin/bash
set -euo pipefail

echo "=== Exporting Theatrical Lighting Booth Setup Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all databases and preferences to disk
echo "Closing Chrome to flush SQLite and JSON data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 4
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Stage files for the verifier
echo "Staging Chrome configuration files..."
cp "/home/ga/.config/google-chrome/Default/Bookmarks" "/tmp/Bookmarks.json" 2>/dev/null || true
cp "/home/ga/.config/google-chrome/Default/Preferences" "/tmp/Preferences.json" 2>/dev/null || true
cp "/home/ga/.config/google-chrome/Local State" "/tmp/Local_State.json" 2>/dev/null || true
cp "/home/ga/.config/google-chrome/Default/Web Data" "/tmp/Web_Data.db" 2>/dev/null || true

# Ensure verifier script can read the staged files
chmod 666 /tmp/Bookmarks.json /tmp/Preferences.json /tmp/Local_State.json /tmp/Web_Data.db 2>/dev/null || true

echo "=== Export Complete ==="