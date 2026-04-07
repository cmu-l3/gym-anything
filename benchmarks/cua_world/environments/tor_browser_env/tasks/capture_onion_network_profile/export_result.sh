#!/bin/bash
# export_result.sh for capture_onion_network_profile task

echo "=== Exporting capture_onion_network_profile results ==="

TASK_NAME="capture_onion_network_profile"
TARGET_FILE="/home/ga/Documents/ddg_onion_profile.har"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Check for HAR file
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Copy the file to tmp so the verifier can copy_from_env
    cp "$TARGET_FILE" "/tmp/exported_profile.har" 2>/dev/null || true
    chmod 666 "/tmp/exported_profile.har" 2>/dev/null || true
fi

# Check Browser History for verification that the URL was actually visited
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

python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/capture_onion_network_profile_places.sqlite"

result = {
    "db_found": False,
    "history_has_ddg_onion": False
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    c.execute("""
        SELECT p.url, p.title
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        GROUP BY p.id
        ORDER BY MAX(h.visit_date) DESC
        LIMIT 100
    """)
    history = [{"url": row["url"] or "", "title": row["title"] or ""} for row in c.fetchall()]

    for h in history:
        url = h["url"].lower()
        if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url:
            result["history_has_ddg_onion"] = True

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Merge metadata into final result
python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db = json.load(f)
except Exception:
    db = {"db_found": False, "history_has_ddg_onion": False}

db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "task_start": $TASK_START
})

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json