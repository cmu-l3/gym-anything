#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Location Scout Workspace Result ==="

# 1. Take final screenshot for VLM verification and debugging
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Record export timestamp
date +%s > /tmp/task_end_time.txt

# 3. Gracefully close Chrome to flush all data (Bookmarks, Preferences, Web Data) to disk
echo "Closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chromium" 2>/dev/null || true

# Wait for Chrome to write out DB files and JSONs
sleep 4

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chromium" 2>/dev/null || true
sleep 1

# 4. Dump search engines from Web Data SQLite to JSON for easier verification by script
WEB_DATA_FILE="/home/ga/.config/google-chrome/Default/Web Data"
DB_DUMP="/tmp/chrome_search_engines.json"

if [ -f "$WEB_DATA_FILE" ]; then
    echo "Extracting search engines from Web Data..."
    python3 << 'PYEOF'
import sqlite3
import json
import sys
import shutil

# Copy the DB just in case it's still locked
shutil.copy2("/home/ga/.config/google-chrome/Default/Web Data", "/tmp/WebData_copy")

try:
    conn = sqlite3.connect("/tmp/WebData_copy")
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT keyword, url FROM keywords")
    rows = cursor.fetchall()
    
    engines = {}
    for r in rows:
        keyword = r['keyword']
        url = r['url']
        if keyword and url:
            engines[keyword] = url
            
    with open("/tmp/chrome_search_engines.json", "w") as f:
        json.dump(engines, f)
except Exception as e:
    with open("/tmp/chrome_search_engines_error.txt", "w") as f:
        f.write(str(e))
finally:
    if 'conn' in locals():
        conn.close()
PYEOF
else:
    echo "Web Data file not found!"
fi

echo "=== Export Complete ==="