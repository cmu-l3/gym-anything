#!/bin/bash
# export_result.sh for configure_multilingual_research task
# Safely extracts data from places.sqlite and prefs.js

echo "=== Exporting configure_multilingual_research results ==="

TASK_NAME="configure_multilingual_research"

# Capture final screenshot
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
        echo "Using Tor Browser profile: $PROFILE_DIR"
        break
    fi
done

PLACES_DB="$PROFILE_DIR/places.sqlite"
PREFS_FILE="$PROFILE_DIR/prefs.js"
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"

# Make copies of the SQLite files to avoid locking issues (handling WAL mode)
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# We use Python to analyze both prefs.js and the sqlite db 
# to ensure precise Unicode handling and JSON serialization
python3 << 'PYEOF' > /tmp/${TASK_NAME}_result.json
import sqlite3
import json
import os
import re

db_path = "/tmp/configure_multilingual_research_places_export.sqlite"
prefs_path = os.environ.get("PREFS_FILE", "")
if not prefs_path:
    # Try to extract from the bash variable if not in env
    prefs_path = "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/prefs.js"
    if not os.path.exists(prefs_path):
        prefs_path = "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/prefs.js"

result = {
    "db_found": False,
    "prefs_found": False,
    "accept_languages_pref": "",
    "folders": [],
    "bookmarks": [],
    "history": []
}

# 1. Read prefs.js for intl.accept_languages
if os.path.exists(prefs_path):
    result["prefs_found"] = True
    try:
        with open(prefs_path, "r", encoding="utf-8") as f:
            for line in f:
                if "intl.accept_languages" in line:
                    # typical format: user_pref("intl.accept_languages", "es-ES, fr-FR, en-US");
                    match = re.search(r'user_pref\("intl\.accept_languages",\s*"([^"]+)"\);', line)
                    if match:
                        result["accept_languages_pref"] = match.group(1)
    except Exception as e:
        result["prefs_error"] = str(e)

# 2. Read places.sqlite for history and bookmarks
if os.path.exists(db_path):
    result["db_found"] = True
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()

        # Folders (type=2)
        c.execute("SELECT id, title FROM moz_bookmarks WHERE type=2 AND title IS NOT NULL")
        folders = [{"id": row["id"], "title": row["title"]} for row in c.fetchall()]
        result["folders"] = folders
        
        folder_map = {f["id"]: f["title"] for f in folders}

        # Bookmarks (type=1)
        c.execute("""
            SELECT b.title, b.parent, p.url 
            FROM moz_bookmarks b
            JOIN moz_places p ON b.fk = p.id
            WHERE b.type=1
        """)
        
        bookmarks = []
        for row in c.fetchall():
            folder_title = folder_map.get(row["parent"], "Unknown")
            bookmarks.append({
                "title": row["title"] or "",
                "url": row["url"] or "",
                "folder": folder_title
            })
        result["bookmarks"] = bookmarks

        # History Visits
        c.execute("""
            SELECT p.url, p.title
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            GROUP BY p.id
            ORDER BY MAX(h.visit_date) DESC
            LIMIT 200
        """)
        history = [{"url": row["url"] or "", "title": row["title"] or ""} for row in c.fetchall()]
        result["history"] = history

        conn.close()
    except Exception as e:
        result["db_error"] = str(e)

print(json.dumps(result, ensure_ascii=False, indent=2))
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Cleanup temp db files
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="