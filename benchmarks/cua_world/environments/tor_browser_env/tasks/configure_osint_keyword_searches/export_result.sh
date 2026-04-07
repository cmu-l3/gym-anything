#!/bin/bash
# export_result.sh for configure_osint_keyword_searches task
# Queries places.sqlite for folders, keywords, and history

echo "=== Exporting configure_osint_keyword_searches results ==="

TASK_NAME="configure_osint_keyword_searches"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find profile and places.sqlite
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

# Make a copy to avoid WAL lock issues while browser is running
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

TASK_START_MICRO=$(cat /tmp/${TASK_NAME}_start_ts_micro 2>/dev/null || echo "0")

# Use Python to query the database
python3 << PYEOF > /tmp/${TASK_NAME}_result.json
import sqlite3
import json
import os

db_path = "/tmp/${TASK_NAME}_places_export.sqlite"
task_start_micro = int("${TASK_START_MICRO}")

result = {
    "db_found": False,
    "folder_exists": False,
    "folder_id": None,
    "keywords": [],
    "bookmarks_in_folder": [],
    "history_urls": [],
    "anti_gaming_passed": True
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # 1. Look for the OSINT Keyword Searches folder
    c.execute("""
        SELECT id, title, dateAdded
        FROM moz_bookmarks
        WHERE type=2 AND title = 'OSINT Keyword Searches'
    """)
    folder = c.fetchone()
    if folder:
        result["folder_exists"] = True
        result["folder_id"] = folder["id"]
        # Anti-gaming: Ensure it was created after task start
        if folder["dateAdded"] and folder["dateAdded"] < task_start_micro:
            result["anti_gaming_passed"] = False

    # 2. Get all keywords globally
    c.execute("""
        SELECT k.keyword, p.url, b.title, b.parent, b.dateAdded
        FROM moz_keywords k
        JOIN moz_places p ON k.place_id = p.id
        LEFT JOIN moz_bookmarks b ON b.fk = p.id
    """)
    for row in c.fetchall():
        kw_info = {
            "keyword": row["keyword"] or "",
            "url": row["url"] or "",
            "title": row["title"] or "",
            "parent_id": row["parent"]
        }
        result["keywords"].append(kw_info)
        
        # Anti-gaming check on keyword bookmarks
        if row["dateAdded"] and row["dateAdded"] < task_start_micro:
            result["anti_gaming_passed"] = False

    # 3. Get all bookmarks in the specific folder (if it exists)
    if result["folder_id"]:
        c.execute("""
            SELECT b.title, p.url, k.keyword
            FROM moz_bookmarks b
            JOIN moz_places p ON b.fk = p.id
            LEFT JOIN moz_keywords k ON k.place_id = p.id
            WHERE b.parent = ? AND b.type = 1
        """, (result["folder_id"],))
        
        for row in c.fetchall():
            result["bookmarks_in_folder"].append({
                "title": row["title"] or "",
                "url": row["url"] or "",
                "keyword": row["keyword"] or ""
            })

    # 4. Get recent history to check if a keyword search was tested
    c.execute("""
        SELECT p.url
        FROM moz_historyvisits h
        JOIN moz_places p ON h.place_id = p.id
        WHERE h.visit_date > ?
        ORDER BY h.visit_date DESC
        LIMIT 50
    """, (task_start_micro,))
    
    result["history_urls"] = [row["url"] for row in c.fetchall()]

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json