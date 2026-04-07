#!/bin/bash
# export_result.sh for tor_accessibility_fingerprinting_audit task

echo "=== Exporting tor_accessibility_fingerprinting_audit results ==="

TASK_NAME="tor_accessibility_fingerprinting_audit"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# 1. Check if the output file exists and get its metadata
TARGET_FILE="/home/ga/Documents/a11y_audit.txt"
FILE_EXISTS="false"
FILE_IS_NEW="false"
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# 2. Check Tor Browser profile for Prefs and DB
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

# Evaluate Preferences
A11Y_PREF_MODIFIED="false"
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/prefs.js" ]; then
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    # User might have enabled devtools.accessibility.enabled=true or accessibility.force_disabled=0
    if grep -q 'devtools\.accessibility\.enabled.*true' "$PREFS_FILE" 2>/dev/null; then
        A11Y_PREF_MODIFIED="true"
    elif grep -q 'accessibility\.force_disabled.*0' "$PREFS_FILE" 2>/dev/null; then
        A11Y_PREF_MODIFIED="true"
    fi
fi

# Evaluate Database (History & Bookmarks)
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"

if [ -f "$PLACES_DB" ]; then
    # Use python script to query securely bypassing WAL locks
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/tor_accessibility_fingerprinting_audit_places.sqlite"

result = {
    "db_found": False,
    "history_has_tor_check": False,
    "bookmark_target_exists": False
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
        SELECT p.url
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
    """)
    for row in c.fetchall():
        if "check.torproject.org" in (row["url"] or "").lower():
            result["history_has_tor_check"] = True

    # Check bookmarks
    c.execute("""
        SELECT b.title, p.url
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        WHERE b.type=1
    """)
    for row in c.fetchall():
        if row["title"] == "Tor A11y Target" and "check.torproject.org" in (row["url"] or "").lower():
            result["bookmark_target_exists"] = True

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Merge all results
python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db = json.load(f)
except:
    db = {}

db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "a11y_pref_modified": $A11Y_PREF_MODIFIED,
    "task_start": $TASK_START
})

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json