#!/bin/bash
# export_result.sh - Post-task hook for verify_onion_location_header task
# Exports file status, contents, and SQLite queries to JSON

echo "=== Exporting verify_onion_location_header results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

TARGET_FILE="/home/ga/Documents/onion_location_audit.txt"
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_CONTENT=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIMESTAMP" ]; then
        FILE_IS_NEW="true"
    fi
    # Read the first few lines of the file safely to include in JSON
    FILE_CONTENT=$(head -n 10 "$TARGET_FILE" | base64 -w 0 2>/dev/null)
fi

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
TEMP_DB="/tmp/places_export_$$.sqlite"

# Copy database to avoid WAL locks
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Query places.sqlite with python
python3 << 'PYEOF' > /tmp/db_query_result.json
import sqlite3
import json
import os

db_path = "/tmp/places_export_{}.sqlite".format(os.getpid())
result = {
    "db_found": False,
    "bookmarks": [],
    "history": []
}

if os.path.exists(db_path):
    result["db_found"] = True
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()

        # Get bookmarks
        c.execute("""
            SELECT b.title, p.url 
            FROM moz_bookmarks b 
            JOIN moz_places p ON b.fk = p.id 
            WHERE b.type=1
        """)
        result["bookmarks"] = [{"title": row["title"] or "", "url": row["url"] or ""} for row in c.fetchall()]

        # Get history
        c.execute("""
            SELECT p.url, p.title 
            FROM moz_places p 
            JOIN moz_historyvisits h ON p.id = h.place_id 
            GROUP BY p.id 
            ORDER BY MAX(h.visit_date) DESC 
            LIMIT 100
        """)
        result["history"] = [row["url"] for row in c.fetchall()]

        conn.close()
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Merge into a final JSON
python3 << PYEOF2
import json

db_result = {}
try:
    with open('/tmp/db_query_result.json', 'r') as f:
        db_result = json.load(f)
except:
    pass

final_result = {
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_content_base64": "$FILE_CONTENT",
    "db": db_result
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
PYEOF2

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/db_query_result.json 2>/dev/null || true

echo "=== Export Complete ==="