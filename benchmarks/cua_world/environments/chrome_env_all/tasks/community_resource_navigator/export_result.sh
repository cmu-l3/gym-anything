#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Community Resource Navigator Result ==="

# Record task end time
date +%s > /tmp/export_timestamp.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all SQLite DBs and JSON files to disk
echo "Closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome" 2>/dev/null || true
sleep 3

# Force kill if still lingering
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Prepare export directory
EXPORT_DIR="/tmp/chrome_export"
mkdir -p "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
CHROME_CONFIG="/home/ga/.config/google-chrome"

# 1. Copy JSON config files safely
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" "$EXPORT_DIR/Bookmarks.json"
else
    echo "{}" > "$EXPORT_DIR/Bookmarks.json"
fi

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$EXPORT_DIR/Preferences.json"
else
    echo "{}" > "$EXPORT_DIR/Preferences.json"
fi

if [ -f "$CHROME_CONFIG/Local State" ]; then
    cp "$CHROME_CONFIG/Local State" "$EXPORT_DIR/Local_State.json"
else
    echo "{}" > "$EXPORT_DIR/Local_State.json"
fi

# 2. Extract Custom Search Engines from Web Data SQLite DB
# Chrome stores custom search engines in the `keywords` table of `Web Data`
echo "[]" > "$EXPORT_DIR/search_engines.json"
if [ -f "$CHROME_PROFILE/Web Data" ]; then
    # Use python to extract to avoid sqlite3 json dependency issues on some older ubuntu versions
    python3 << PYEOF
import sqlite3
import json

try:
    conn = sqlite3.connect("$CHROME_PROFILE/Web Data")
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT short_name, keyword, url FROM keywords")
    rows = [dict(row) for row in cursor.fetchall()]
    with open("$EXPORT_DIR/search_engines.json", "w") as f:
        json.dump(rows, f)
except Exception as e:
    print(f"Error reading Web Data: {e}")
PYEOF
fi

chmod -R 777 "$EXPORT_DIR"

echo "=== Export Complete ==="