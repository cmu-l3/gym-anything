#!/bin/bash
set -euo pipefail

echo "=== Exporting Genealogy Reading Room Task Result ==="

# Record export start time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close Chrome gracefully to ensure Preferences, Bookmarks, Web Data, and Local State are flushed to disk
echo "Closing Chrome to flush SQLite and JSON data..."
pkill -f "chrome" 2>/dev/null || true
sleep 3

# Force kill any lingering processes
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Confirm files exist
ls -l "/home/ga/.config/google-chrome/Local State" "/home/ga/.config/google-chrome/Default/Preferences" "/home/ga/.config/google-chrome/Default/Web Data" "/home/ga/.config/google-chrome/Default/Bookmarks" > /tmp/chrome_files_status.txt 2>&1 || true

echo "=== Export Complete ==="