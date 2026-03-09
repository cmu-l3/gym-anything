#!/bin/bash
# export_result.sh for secure_bookmark_management task
# Queries places.sqlite for bookmark folders, bookmark titles, and visit history

echo "=== Exporting secure_bookmark_management results ==="

TASK_NAME="secure_bookmark_management"

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
    # Also copy WAL file if it exists
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Use Python to query the database (handles WAL mode better)
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/secure_bookmark_management_places_export.sqlite"

result = {
    "db_found": False,
    "folders": [],
    "bookmarks": [],
    "history_urls": [],
    "folder_secure_research": False,
    "folder_press_freedom": False,
    "bookmark_ddg_onion_in_secure_folder": False,
    "bookmark_tor_checker_in_secure_folder": False,
    "bookmark_in_press_freedom_folder": False,
    "ddg_onion_title_correct": False,
    "tor_checker_title_correct": False,
    "history_has_check_torproject": False,
    "history_has_ddg_onion": False,
    "history_has_ddg_search": False
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Get all bookmark folders (type=2)
    c.execute("""
        SELECT id, title, parent FROM moz_bookmarks
        WHERE type=2 AND title IS NOT NULL AND title != ''
        ORDER BY dateAdded DESC
    """)
    folders = [{"id": row["id"], "title": row["title"], "parent": row["parent"]} for row in c.fetchall()]
    result["folders"] = [f["title"] for f in folders]

    # Check for required folders (case-sensitive exact match)
    folder_map = {f["title"]: f["id"] for f in folders}

    result["folder_secure_research"] = "Secure Research Sources" in folder_map
    result["folder_press_freedom"] = "Press Freedom Research" in folder_map

    # Get all bookmarks with their folder names
    c.execute("""
        SELECT b.id, b.title, b.parent, p.url,
               bf.title as folder_title
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        LEFT JOIN moz_bookmarks bf ON b.parent = bf.id
        WHERE b.type=1
        ORDER BY b.dateAdded DESC
    """)
    bookmarks = []
    for row in c.fetchall():
        bookmarks.append({
            "title": row["title"] or "",
            "url": row["url"] or "",
            "folder": row["folder_title"] or ""
        })
    result["bookmarks"] = bookmarks

    # Check bookmark in "Secure Research Sources" folder
    ddg_onion_domain = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
    tor_checker_domain = "check.torproject.org"

    for bm in bookmarks:
        if bm["folder"] == "Secure Research Sources":
            if ddg_onion_domain in bm["url"]:
                result["bookmark_ddg_onion_in_secure_folder"] = True
                if bm["title"] == "DuckDuckGo Private Search":
                    result["ddg_onion_title_correct"] = True
            if tor_checker_domain in bm["url"]:
                result["bookmark_tor_checker_in_secure_folder"] = True
                if bm["title"] == "Tor Exit Node Checker":
                    result["tor_checker_title_correct"] = True
        if bm["folder"] == "Press Freedom Research":
            result["bookmark_in_press_freedom_folder"] = True

    # Check browser history
    c.execute("""
        SELECT p.url, p.title
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        GROUP BY p.id
        ORDER BY MAX(h.visit_date) DESC
        LIMIT 100
    """)
    history = [{"url": row["url"], "title": row["title"] or ""} for row in c.fetchall()]
    result["history_urls"] = [h["url"] for h in history[:20]]  # Top 20 for evidence

    for h in history:
        url = h["url"].lower()
        if "check.torproject.org" in url:
            result["history_has_check_torproject"] = True
        if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url:
            result["history_has_ddg_onion"] = True
        if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url and "?" in url:
            result["history_has_ddg_search"] = True
        if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url and "q=" in url:
            result["history_has_ddg_search"] = True

    conn.close()

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Load db result and merge with base result
DB_RESULT=$(cat /tmp/${TASK_NAME}_db_result.json 2>/dev/null || echo '{}')

INITIAL_COUNT=$(cat /tmp/${TASK_NAME}_initial_bookmark_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

TOR_RUNNING="false"
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null && TOR_RUNNING="true"

# Write final result JSON
python3 << PYEOF2
import json

db = json.load(open('/tmp/${TASK_NAME}_db_result.json'))
db['initial_bookmark_count'] = $INITIAL_COUNT
db['task_start'] = $TASK_START
db['tor_browser_running'] = $TOR_RUNNING

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
print("Result written")
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Cleanup
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json
