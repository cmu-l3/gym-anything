#!/bin/bash
set -euo pipefail

echo "=== Exporting SRE Incident Command Setup Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract active tabs via CDP while Chrome is still running
echo "Extracting CDP live tabs..."
curl -s http://localhost:9222/json > /tmp/cdp_tabs_export.json || echo "[]" > /tmp/cdp_tabs_export.json

# 3. Gracefully close Chrome so it writes Preferences, Local State, and Bookmarks to disk
echo "Gracefully closing Chrome to flush databases..."
pkill -15 -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -15 -f "google-chrome" 2>/dev/null || true
sleep 4

# Force kill if it's hung
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 4. Copy configurations to /tmp for verifier access
CHROME_DIR="/home/ga/.config/google-chrome"

echo "Copying config files..."
cp "$CHROME_DIR/Default/Bookmarks" /tmp/Bookmarks_export.json 2>/dev/null || echo "{}" > /tmp/Bookmarks_export.json
cp "$CHROME_DIR/Default/Preferences" /tmp/Preferences_export.json 2>/dev/null || echo "{}" > /tmp/Preferences_export.json
cp "$CHROME_DIR/Local State" /tmp/LocalState_export.json 2>/dev/null || echo "{}" > /tmp/LocalState_export.json

# 5. Extract custom search engines from SQLite Web Data
echo "Extracting Web Data keywords..."
if command -v sqlite3 &> /dev/null; then
    sqlite3 "$CHROME_DIR/Default/Web Data" "SELECT keyword, url FROM keywords;" > /tmp/keywords_export.txt 2>/dev/null || echo "" > /tmp/keywords_export.txt
else
    echo "" > /tmp/keywords_export.txt
fi

# Ensure files are readable
chmod 666 /tmp/*_export.* /tmp/task_*.txt /tmp/task_*.png 2>/dev/null || true

echo "=== Export Complete ==="