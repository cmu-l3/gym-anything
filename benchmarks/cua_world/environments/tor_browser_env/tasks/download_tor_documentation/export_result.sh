#!/bin/bash
# export_result.sh for download_tor_documentation task
# Checks for downloaded file, history, and bookmarks

echo "=== Exporting download_tor_documentation results ==="

TASK_NAME="download_tor_documentation"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Check 1: Target file exists at correct location
TARGET_FILE="/home/ga/Documents/tor-dir-spec.txt"
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0
FILE_HAS_TOR_CONTENT="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    # Check that it actually contains Tor specification content
    if grep -qi "tor\|directory\|protocol\|spec" "$TARGET_FILE" 2>/dev/null; then
        FILE_HAS_TOR_CONTENT="true"
    fi
fi
echo "Target file exists: $FILE_EXISTS (new: $FILE_IS_NEW, size: ${FILE_SIZE}B, has_tor_content: $FILE_HAS_TOR_CONTENT)"

# Also check Downloads folder for any .txt files (agent might have put it there)
FILES_IN_DOWNLOADS=$(ls /home/ga/Downloads/*.txt 2>/dev/null | wc -l || echo "0")

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

# Copy database
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Query history and bookmarks
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/download_tor_documentation_places.sqlite"

result = {
    "db_found": False,
    "history_has_spec_torproject": False,
    "history_has_tor_history_page": False,
    "bookmark_spec_torproject": False,
    "bookmark_spec_title_correct": False
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Check history
    c.execute("""
        SELECT p.url, p.title
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        GROUP BY p.id
        ORDER BY MAX(h.visit_date) DESC
        LIMIT 200
    """)
    history = [{"url": row["url"] or "", "title": row["title"] or ""} for row in c.fetchall()]

    for h in history:
        url = h["url"].lower()
        if "spec.torproject.org" in url:
            result["history_has_spec_torproject"] = True
        if "torproject.org/about/history" in url:
            result["history_has_tor_history_page"] = True

    # Check bookmarks for spec.torproject.org
    c.execute("""
        SELECT b.title, p.url
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        WHERE b.type=1
        ORDER BY b.dateAdded DESC
    """)
    bookmarks = [{"title": row["title"] or "", "url": row["url"] or ""} for row in c.fetchall()]

    for bm in bookmarks:
        if "spec.torproject.org" in bm["url"].lower():
            result["bookmark_spec_torproject"] = True
            if bm["title"] == "Tor Protocol Specifications":
                result["bookmark_spec_title_correct"] = True

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Build final result
TOR_RUNNING="false"
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null && TOR_RUNNING="true"

python3 << PYEOF2
import json

db = json.load(open('/tmp/${TASK_NAME}_db_result.json'))
db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "file_has_tor_content": $FILE_HAS_TOR_CONTENT,
    "task_start": $TASK_START,
    "tor_browser_running": $TOR_RUNNING
})
with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
print("Result written")
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json
