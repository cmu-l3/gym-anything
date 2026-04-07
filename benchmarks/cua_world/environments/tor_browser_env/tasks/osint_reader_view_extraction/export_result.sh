#!/bin/bash
# export_result.sh for osint_reader_view_extraction task

echo "=== Exporting osint_reader_view_extraction results ==="

TASK_NAME="osint_reader_view_extraction"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Check Extracted Text File
TARGET_FILE="/home/ga/Documents/osint_clean_extract.txt"
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0
HAS_KEYWORDS="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    if grep -qiE "open-source intelligence|osint" "$TARGET_FILE" 2>/dev/null; then
        HAS_KEYWORDS="true"
    fi
fi

# Find Profile for settings and bookmarks
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

PREFS_FILE="$PROFILE_DIR/prefs.js"
THEME=""
FONT=""

# Retrieve typography settings
if [ -f "$PREFS_FILE" ]; then
    THEME=$(grep "reader.color_theme" "$PREFS_FILE" 2>/dev/null | grep -oP '"\K[^"]+(?="\))' | tail -1 || echo "")
    if [ -z "$THEME" ]; then
        THEME=$(grep "reader.color_theme" "$PREFS_FILE" 2>/dev/null | cut -d',' -f2 | tr -d ' ");\n' || echo "")
    fi
    FONT=$(grep "reader.font_type" "$PREFS_FILE" 2>/dev/null | grep -oP '"\K[^"]+(?="\))' | tail -1 || echo "")
    if [ -z "$FONT" ]; then
        FONT=$(grep "reader.font_type" "$PREFS_FILE" 2>/dev/null | cut -d',' -f2 | tr -d ' ");\n' || echo "")
    fi
fi

# Bookmarks Check via places.sqlite
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

db_path = "/tmp/osint_reader_view_extraction_places.sqlite"
result = {
    "bookmark_exists": False,
    "bookmark_url_correct": False,
    "db_found": False
}

if os.path.exists(db_path):
    result["db_found"] = True
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        c.execute("""
            SELECT b.title, p.url 
            FROM moz_bookmarks b
            JOIN moz_places p ON b.fk = p.id
            WHERE b.type=1 AND b.title = 'OSINT Clean Reading'
        """)
        rows = c.fetchall()
        if rows:
            result["bookmark_exists"] = True
            for r in rows:
                url = r["url"] or ""
                if url.startswith("about:reader?url="):
                    result["bookmark_url_correct"] = True
                    break
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Consolidate Output Data
python3 << PYEOF2
import json

db = json.load(open('/tmp/${TASK_NAME}_db_result.json'))
db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "has_keywords": $HAS_KEYWORDS,
    "reader_theme": "$THEME",
    "reader_font": "$FONT",
    "task_start": $TASK_START
})
with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json