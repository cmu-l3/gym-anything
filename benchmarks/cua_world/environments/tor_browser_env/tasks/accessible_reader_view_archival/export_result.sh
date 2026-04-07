#!/bin/bash
# export_result.sh for accessible_reader_view_archival task
# Checks for the PDF, its magic bytes, and reader view history/prefs

echo "=== Exporting accessible_reader_view_archival results ==="

TASK_NAME="accessible_reader_view_archival"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/accessible_article.pdf"

# Initialize variables
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0
IS_VALID_PDF="false"

# Check 1: Target PDF File
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Verify magic bytes (starts with %PDF)
    MAGIC_BYTES=$(head -c 4 "$TARGET_FILE" 2>/dev/null || echo "")
    if [ "$MAGIC_BYTES" = "%PDF" ]; then
        IS_VALID_PDF="true"
    fi
fi
echo "PDF exists: $FILE_EXISTS (new: $FILE_IS_NEW, valid: $IS_VALID_PDF, size: ${FILE_SIZE}B)"

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

PREFS_FILE="$PROFILE_DIR/prefs.js"
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Check 2: Reader View Preferences
THEME="light" # default
FONT="sans-serif" # default
if [ -f "$PREFS_FILE" ]; then
    # Extract reader.color_theme
    THEME_VAL=$(grep "reader.color_theme" "$PREFS_FILE" 2>/dev/null | grep -oP '"\K[^"]+(?="\);)' | tail -1 || echo "")
    if [ -n "$THEME_VAL" ]; then THEME="$THEME_VAL"; fi
    
    # Extract reader.font_type
    FONT_VAL=$(grep "reader.font_type" "$PREFS_FILE" 2>/dev/null | grep -oP '"\K[^"]+(?="\);)' | tail -1 || echo "")
    if [ -n "$FONT_VAL" ]; then FONT="$FONT_VAL"; fi
fi
echo "Reader Theme: $THEME | Reader Font: $FONT"

# Check 3: History for about:reader
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

python3 << PYEOF > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/${TASK_NAME}_places.sqlite"
result = {"reader_view_used": False}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places WHERE url LIKE 'about:reader?url=%wikipedia.org/wiki/Internet_censorship%'")
        rows = c.fetchall()
        result["reader_view_used"] = len(rows) > 0
        conn.close()
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

READER_USED=$(python3 -c "import json; print(json.load(open('/tmp/${TASK_NAME}_db_result.json')).get('reader_view_used', False))" | tr '[:upper:]' '[:lower:]')
echo "Reader View Used in History: $READER_USED"

# Build final result JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "is_valid_pdf": $IS_VALID_PDF,
    "reader_theme": "$THEME",
    "reader_font": "$FONT",
    "reader_view_used": $READER_USED,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json