#!/bin/bash
# export_result.sh for configure_low_bandwidth_tor_profile task

echo "=== Exporting configure_low_bandwidth_tor_profile results ==="

TASK_NAME="configure_low_bandwidth_tor_profile"

# Take final screenshot of the full screen
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Check 1: Output screenshot file exists and was created during the task
TARGET_FILE="/home/ga/Documents/low_bandwidth_test.png"
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
fi
echo "Screenshot file exists: $FILE_EXISTS (new: $FILE_IS_NEW, size: ${FILE_SIZE}B)"

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
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"

# Check 2: Parse prefs.js for the integer values
PREF_IMAGE="-1"
PREF_FONTS="-1"
PREF_MEDIA="-1"
PREFS_FOUND="false"

if [ -f "$PREFS_FILE" ]; then
    PREFS_FOUND="true"
    # Firefox stores them as user_pref("key", value);
    VAL_IMG=$(grep -oP 'user_pref\("permissions\.default\.image",\s*\K[0-9]+' "$PREFS_FILE" 2>/dev/null || echo "-1")
    if [ -n "$VAL_IMG" ]; then PREF_IMAGE="$VAL_IMG"; fi

    VAL_FNT=$(grep -oP 'user_pref\("browser\.display\.use_document_fonts",\s*\K[0-9]+' "$PREFS_FILE" 2>/dev/null || echo "-1")
    if [ -n "$VAL_FNT" ]; then PREF_FONTS="$VAL_FNT"; fi

    VAL_MED=$(grep -oP 'user_pref\("media\.autoplay\.default",\s*\K[0-9]+' "$PREFS_FILE" 2>/dev/null || echo "-1")
    if [ -n "$VAL_MED" ]; then PREF_MEDIA="$VAL_MED"; fi
fi

echo "Parsed Prefs - Image: $PREF_IMAGE, Fonts: $PREF_FONTS, Media: $PREF_MEDIA"

# Copy database to check history safely
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Query history using Python
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/configure_low_bandwidth_tor_profile_places.sqlite"

result = {
    "db_found": False,
    "history_has_wikipedia": False
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
        LIMIT 200
    """)
    history = [{"url": row["url"] or ""} for row in c.fetchall()]

    for h in history:
        url = h["url"].lower()
        if "en.wikipedia.org" in url:
            result["history_has_wikipedia"] = True
            break

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

TOR_RUNNING="false"
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null && TOR_RUNNING="true"

# Merge all results into a single JSON
python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db = json.load(f)
except:
    db = {"db_found": False, "history_has_wikipedia": False}

db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "prefs_found": $PREFS_FOUND,
    "pref_image": int("$PREF_IMAGE"),
    "pref_fonts": int("$PREF_FONTS"),
    "pref_media": int("$PREF_MEDIA"),
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