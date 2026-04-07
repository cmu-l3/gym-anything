#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Field Terminal Browser Config Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gracefully close Chrome to flush Preferences and Bookmarks to disk
echo "Closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 3. Export end timestamp
date +%s > /tmp/task_end_time.txt

# 4. Copy current Preferences and Bookmarks to /tmp/ to ensure accessible permissions
CDP_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CDP_PROFILE/Preferences" ]; then
    cp "$CDP_PROFILE/Preferences" /tmp/final_preferences.json
    chmod 644 /tmp/final_preferences.json
fi

if [ -f "$CDP_PROFILE/Bookmarks" ]; then
    cp "$CDP_PROFILE/Bookmarks" /tmp/final_bookmarks.json
    chmod 644 /tmp/final_bookmarks.json
fi

echo "=== Export complete ==="