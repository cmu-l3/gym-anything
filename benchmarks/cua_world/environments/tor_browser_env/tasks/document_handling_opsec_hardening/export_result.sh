#!/bin/bash
# export_result.sh for document_handling_opsec_hardening
# Evaluates prefs.js, quarantine directory, file downloads, and history.

echo "=== Exporting document_handling_opsec_hardening results ==="

TASK_NAME="document_handling_opsec_hardening"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# 2. Check File System details
QUARANTINE_DIR="/home/ga/Documents/Quarantine"
TARGET_FILE="$QUARANTINE_DIR/rfc8446.pdf"

DIR_EXISTS="false"
if [ -d "$QUARANTINE_DIR" ]; then
    DIR_EXISTS="true"
fi

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# 3. Check Tor Browser Profile (Prefs & History)
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

PREFS_EXISTS="false"
PDFJS_DISABLED="false"
WEBGL_DISABLED="false"
WASM_DISABLED="false"

if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
    # Check for specific configured preferences
    grep -q 'user_pref("pdfjs.disabled", true);' "$PREFS_FILE" 2>/dev/null && PDFJS_DISABLED="true"
    grep -q 'user_pref("webgl.disabled", true);' "$PREFS_FILE" 2>/dev/null && WEBGL_DISABLED="true"
    grep -q 'user_pref("javascript.options.wasm", false);' "$PREFS_FILE" 2>/dev/null && WASM_DISABLED="true"
fi

# Copy database to avoid WAL locks
HISTORY_RFC_VISITED="false"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true

    # Extract history info via Python to avoid bash sqlite3 parsing headaches
    python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/document_handling_opsec_hardening_places.sqlite"
result = {"history_rfc_visited": False}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places WHERE url LIKE '%rfc-editor.org%'")
        if c.fetchone():
            result["history_rfc_visited"] = True
        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open(f"/tmp/document_handling_opsec_hardening_db_result.json", "w") as f:
    json.dump(result, f)
PYEOF

    HISTORY_RFC_VISITED=$(python3 -c "import json; print(json.load(open('/tmp/${TASK_NAME}_db_result.json')).get('history_rfc_visited', False))" | tr 'A-Z' 'a-z')
fi

# 4. Determine if Tor is running
TOR_RUNNING="false"
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null && TOR_RUNNING="true"

# 5. Build final output JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "prefs_file_exists": $PREFS_EXISTS,
    "pdfjs_disabled": $PDFJS_DISABLED,
    "webgl_disabled": $WEBGL_DISABLED,
    "wasm_disabled": $WASM_DISABLED,
    "dir_exists": $DIR_EXISTS,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "history_rfc_visited": $HISTORY_RFC_VISITED,
    "tor_browser_running": $TOR_RUNNING,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json