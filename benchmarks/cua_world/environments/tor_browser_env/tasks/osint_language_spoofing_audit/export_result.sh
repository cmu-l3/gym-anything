#!/bin/bash
# export_result.sh for osint_language_spoofing_audit task

echo "=== Exporting osint_language_spoofing_audit results ==="

TASK_NAME="osint_language_spoofing_audit"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for output files
RU_FILE="/home/ga/Documents/headers_ru.json"
EN_FILE="/home/ga/Documents/headers_en.json"

RU_EXISTS="false"
RU_IS_NEW="false"
EN_EXISTS="false"
EN_IS_NEW="false"

if [ -f "$RU_FILE" ]; then
    RU_EXISTS="true"
    RU_MTIME=$(stat -c %Y "$RU_FILE" 2>/dev/null || echo "0")
    if [ "$RU_MTIME" -gt "$TASK_START" ]; then
        RU_IS_NEW="true"
    fi
fi

if [ -f "$EN_FILE" ]; then
    EN_EXISTS="true"
    EN_MTIME=$(stat -c %Y "$EN_FILE" 2>/dev/null || echo "0")
    if [ "$EN_MTIME" -gt "$TASK_START" ]; then
        EN_IS_NEW="true"
    fi
fi

# 3. Read Tor Profile state
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

# 4. Check OPSEC restoration in prefs.js
SPOOF_ENGLISH_VAL="true" # Tor default is true
if [ -f "$PREFS_FILE" ]; then
    # If explicitly set to false, it will be in prefs.js
    if grep -q 'user_pref("privacy.spoof_english", false);' "$PREFS_FILE"; then
        SPOOF_ENGLISH_VAL="false"
    elif grep -q 'user_pref("privacy.spoof_english", true);' "$PREFS_FILE"; then
        SPOOF_ENGLISH_VAL="true"
    fi
fi

# 5. Check history for httpbin.org
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

python3 << PYEOF > /tmp/${TASK_NAME}_history.json
import sqlite3
import json
import os

db_path = "/tmp/${TASK_NAME}_places.sqlite"
visited_httpbin = False

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places WHERE url LIKE '%httpbin.org/headers%'")
        if c.fetchone():
            visited_httpbin = True
        conn.close()
    except Exception as e:
        pass

print(json.dumps({"visited_httpbin": visited_httpbin}))
PYEOF

VISITED_HTTPBIN=$(python3 -c "import json; print(json.load(open('/tmp/${TASK_NAME}_history.json'))['visited_httpbin'])" | tr '[:upper:]' '[:lower:]')

# 6. Export everything to JSON
cat > /tmp/task_result.json << EOF
{
    "ru_file_exists": $RU_EXISTS,
    "ru_file_is_new": $RU_IS_NEW,
    "en_file_exists": $EN_EXISTS,
    "en_file_is_new": $EN_IS_NEW,
    "privacy_spoof_english": $SPOOF_ENGLISH_VAL,
    "visited_httpbin": $VISITED_HTTPBIN,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_history.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json