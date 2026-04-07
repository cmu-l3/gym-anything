#!/bin/bash
# export_result.sh for compile_privacy_resource_bibliography task
# Gathers file info, copies the file, and extracts browsing history

echo "=== Exporting compile_privacy_resource_bibliography results ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/privacy_research_bibliography.txt"
EXPORT_FILE="/tmp/bibliography_export.txt"

# 2. Check the bibliography file
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
    
    # Copy the file so the verifier can read its contents safely
    cp "$TARGET_FILE" "$EXPORT_FILE" 2>/dev/null
    chmod 644 "$EXPORT_FILE" 2>/dev/null || true
fi

# 3. Find Tor Browser profile and copy places.sqlite
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
TEMP_DB="/tmp/places_export.sqlite"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# 4. Use Python to safely query the history DB
python3 << 'PYEOF' > /tmp/db_result.json
import sqlite3
import json
import os

db_path = "/tmp/places_export.sqlite"

result = {
    "db_found": False,
    "history_urls": []
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Get recent history URLs
    c.execute("""
        SELECT p.url, p.title
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        GROUP BY p.id
        ORDER BY MAX(h.visit_date) DESC
        LIMIT 200
    """)
    history = [{"url": row["url"] or "", "title": row["title"] or ""} for row in c.fetchall()]
    
    # Filter for URLs relevant to the task to keep JSON small
    relevant_urls = []
    for h in history:
        url = h["url"].lower()
        if "eff.org" in url or "torproject.org" in url or "freedom.press" in url or "privacyguides.org" in url:
            relevant_urls.append(url)
            
    result["history_urls"] = relevant_urls

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# 5. Merge file stats and history into the final JSON result
python3 << PYEOF2
import json

try:
    with open('/tmp/db_result.json', 'r') as f:
        db = json.load(f)
except:
    db = {"db_found": False, "history_urls": []}

db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "task_start": $TASK_START
})

with open('/tmp/task_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/task_result.json 2>/dev/null || true

# Cleanup
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json