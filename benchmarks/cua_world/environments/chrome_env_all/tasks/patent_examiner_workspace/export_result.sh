#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Patent Examiner Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Export active tabs via CDP
echo "Exporting open tabs..."
curl -s http://localhost:9222/json > /tmp/tabs_export.json || echo "[]" > /tmp/tabs_export.json

# 2. Gracefully close Chrome to flush Preferences, Bookmarks, and Web Data to disk
echo "Closing Chrome to flush SQLite and JSON data..."
pkill -f "chrome" 2>/dev/null || true
sleep 4

# 3. Export custom search engines from SQLite 'Web Data'
# (Search engines are stored here in modern Chrome, not in Preferences JSON)
WEB_DATA="/home/ga/.config/google-chrome/Default/Web Data"
if [ -f "$WEB_DATA" ]; then
    sqlite3 "$WEB_DATA" "SELECT keyword, url FROM keywords" > /tmp/keywords_export.txt 2>/dev/null || true
else
    echo "" > /tmp/keywords_export.txt
fi

# 4. Export History to text (avoids locking issues when copying binary DBs)
HISTORY_DB="/home/ga/.config/google-chrome/Default/History"
if [ -f "$HISTORY_DB" ]; then
    sqlite3 "$HISTORY_DB" "SELECT url FROM urls" > /tmp/history_export.txt 2>/dev/null || true
else
    echo "" > /tmp/history_export.txt
fi

echo "=== Export Complete ==="