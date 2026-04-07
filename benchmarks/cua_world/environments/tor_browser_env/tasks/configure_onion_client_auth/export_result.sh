#!/bin/bash
# export_result.sh for configure_onion_client_auth task
# Collects evidence from Tor daemon auth folder, browser prefs, and bookmarks database

echo "=== Exporting configure_onion_client_auth results ==="

TASK_NAME="configure_onion_client_auth"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Locate Tor Browser directories
BASE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        BASE_DIR="$candidate"
        break
    fi
done

AUTH_FILE_EXISTS="false"
AUTH_FILE_CONTENT=""
AUTH_FILE_IS_NEW="false"
SECURITY_SLIDER=1
PLACES_DB_FOUND="false"

if [ -n "$BASE_DIR" ]; then
    PROFILE_DIR="$BASE_DIR/Browser/TorBrowser/Data/Browser/profile.default"
    ONION_AUTH_DIR="$BASE_DIR/Browser/TorBrowser/Data/Tor/onion-auth"
    
    # 1. Check Onion Auth Key File
    if [ -d "$ONION_AUTH_DIR" ]; then
        # Check for any .auth_private file
        AUTH_FILE=$(ls -1 "$ONION_AUTH_DIR"/*.auth_private 2>/dev/null | head -1 || echo "")
        if [ -n "$AUTH_FILE" ] && [ -f "$AUTH_FILE" ]; then
            AUTH_FILE_EXISTS="true"
            AUTH_FILE_CONTENT=$(cat "$AUTH_FILE" | tr -d '\n' | tr -d '\r')
            
            # Check modification time
            FILE_MTIME=$(stat -c %Y "$AUTH_FILE" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
                AUTH_FILE_IS_NEW="true"
            fi
        fi
    fi

    # 2. Check Security Level
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        SLIDER_VAL=$(grep "browser.security_level.security_slider" "$PREFS_FILE" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "1")
        if [ -n "$SLIDER_VAL" ]; then
            SECURITY_SLIDER=$SLIDER_VAL
        fi
    fi

    # 3. Copy places.sqlite for bookmark verification
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
    if [ -f "$PLACES_DB" ]; then
        PLACES_DB_FOUND="true"
        cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
        [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
        [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
    fi
fi

# Query Bookmarks via Python
python3 << 'PYEOF' > /tmp/${TASK_NAME}_bookmarks.json
import sqlite3
import json
import os

db_path = "/tmp/configure_onion_client_auth_places.sqlite"
result = {"bookmarks": []}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        c.execute("""
            SELECT b.title, p.url 
            FROM moz_bookmarks b 
            JOIN moz_places p ON b.fk = p.id 
            WHERE b.type=1
        """)
        for row in c.fetchall():
            result["bookmarks"].append({
                "title": row["title"] or "",
                "url": row["url"] or ""
            })
        conn.close()
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Merge into final result JSON
python3 << PYEOF2
import json

bookmarks_data = {"bookmarks": []}
try:
    with open('/tmp/${TASK_NAME}_bookmarks.json', 'r') as f:
        bookmarks_data = json.load(f)
except Exception:
    pass

result = {
    "auth_file_exists": "$AUTH_FILE_EXISTS" == "true",
    "auth_file_is_new": "$AUTH_FILE_IS_NEW" == "true",
    "auth_file_content": "$AUTH_FILE_CONTENT",
    "security_slider": int("$SECURITY_SLIDER"),
    "places_db_found": "$PLACES_DB_FOUND" == "true",
    "bookmarks": bookmarks_data.get("bookmarks", []),
    "task_start_ts": int("$TASK_START")
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_bookmarks.json "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json