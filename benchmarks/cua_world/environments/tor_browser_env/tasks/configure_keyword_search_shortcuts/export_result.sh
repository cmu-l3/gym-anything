#!/bin/bash
# export_result.sh for configure_keyword_search_shortcuts task
# Queries places.sqlite for the created bookmarks, keywords, and history

echo "=== Exporting configure_keyword_search_shortcuts results ==="

TASK_NAME="configure_keyword_search_shortcuts"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"

# Make a copy to avoid WAL lock issues
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Query places.sqlite using Python
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os
import sys

db_path = "/tmp/configure_keyword_search_shortcuts_places_export.sqlite"

result = {
    "db_found": False,
    "folders": [],
    "bookmarks": [],
    "history_urls": []
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    sys.exit(0)

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Get bookmark folders
    c.execute("""
        SELECT title FROM moz_bookmarks
        WHERE type=2 AND title IS NOT NULL AND title != ''
    """)
    result["folders"] = [row["title"] for row in c.fetchall()]

    # Get bookmarks with their keywords and parent folder names
    c.execute("""
        SELECT b.title as title, p.url as url, k.keyword as keyword,
               (SELECT title FROM moz_bookmarks WHERE id = b.parent) as folder_title
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        LEFT JOIN moz_keywords k ON k.place_id = p.id
        WHERE b.type = 1
    """)
    
    for row in c.fetchall():
        result["bookmarks"].append({
            "title": row["title"] or "",
            "url": row["url"] or "",
            "keyword": row["keyword"] or "",
            "folder": row["folder_title"] or ""
        })

    # Get history URLs to verify search execution
    c.execute("""
        SELECT p.url
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        ORDER BY h.visit_date DESC
        LIMIT 200
    """)
    result["history_urls"] = [row["url"] for row in c.fetchall()]

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/${TASK_NAME}_db_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/${TASK_NAME}_db_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

# Clean up
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json