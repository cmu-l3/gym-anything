#!/bin/bash
set -e
echo "=== Exporting verify_tor_anonymity_properties results ==="

TASK_NAME="verify_tor_anonymity_properties"
TARGET_FILE="/home/ga/Documents/anonymity-verification.txt"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0
FILE_CONTENT=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    # Base64 encode content to avoid JSON formatting issues
    FILE_CONTENT=$(head -c 5000 "$TARGET_FILE" | base64 -w 0)
fi

# Find Tor Browser profile
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
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Use Python to extract places info safely handling concurrent DB access
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/verify_tor_anonymity_properties_places.sqlite"

result = {
    "db_found": False,
    "history_has_check_torproject": False,
    "history_has_api_ip": False,
    "bookmark_check_torproject": False,
    "bookmark_title_correct": False
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Query history
    c.execute("""
        SELECT p.url, p.title
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        GROUP BY p.id
    """)
    history = [{"url": row["url"] or "", "title": row["title"] or ""} for row in c.fetchall()]

    for h in history:
        url = h["url"].lower()
        if "check.torproject.org" in url:
            result["history_has_check_torproject"] = True
            if "api/ip" in url:
                result["history_has_api_ip"] = True

    # Query bookmarks
    c.execute("""
        SELECT b.title, p.url
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        WHERE b.type=1
    """)
    bookmarks = [{"title": row["title"] or "", "url": row["url"] or ""} for row in c.fetchall()]

    for bm in bookmarks:
        if "check.torproject.org" in bm["url"].lower():
            result["bookmark_check_torproject"] = True
            if bm["title"] == "Tor Connection Verifier":
                result["bookmark_title_correct"] = True

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Merge all results into the final task_result.json
python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json') as f:
        db = json.load(f)
except:
    db = {}

db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "file_content_b64": "$FILE_CONTENT"
})

with open('/tmp/task_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="