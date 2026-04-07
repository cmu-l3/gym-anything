#!/bin/bash
set -euo pipefail

echo "=== Exporting Web Accessibility Audit Result ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot BEFORE closing Chrome
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Chrome was running
APP_RUNNING=$(pgrep -f "chrome" > /dev/null && echo "true" || echo "false")
echo "Chrome was running: $APP_RUNNING" > /tmp/app_status.txt

# Gracefully close Chrome to flush JSON files and Web Data SQLite DB to disk
echo "Closing Chrome to flush data..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Export SQLite Web Data (Search engines) to JSON for easy parsing by verifier
if [ -f "/home/ga/.config/google-chrome/Default/Web Data" ]; then
    sqlite3 -json "/home/ga/.config/google-chrome/Default/Web Data" "SELECT keyword, url FROM keywords;" > /tmp/search_engines.json 2>/dev/null || echo "[]" > /tmp/search_engines.json
else
    echo "[]" > /tmp/search_engines.json
fi
chmod 666 /tmp/search_engines.json

echo "=== Export complete ==="