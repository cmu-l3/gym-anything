#!/bin/bash
echo "=== Exporting configure_local_onion_service results ==="

TASK_NAME="configure_local_onion_service"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Check if torrc was configured
TORRC_PATH=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Tor/torrc" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Tor/torrc" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Tor/torrc"
do
    if [ -f "$candidate" ]; then
        TORRC_PATH="$candidate"
        break
    fi
done

HAS_HIDDEN_SERVICE_DIR="false"
HAS_HIDDEN_SERVICE_PORT="false"
if [ -n "$TORRC_PATH" ]; then
    if grep -q "HiddenServiceDir.*/home/ga/Documents/local_onion" "$TORRC_PATH"; then
        HAS_HIDDEN_SERVICE_DIR="true"
    fi
    if grep -q "HiddenServicePort.*80.*127.0.0.1:8080" "$TORRC_PATH"; then
        HAS_HIDDEN_SERVICE_PORT="true"
    fi
fi

# Check directory permissions
DIR_EXISTS="false"
DIR_PERMS=""
if [ -d "/home/ga/Documents/local_onion" ]; then
    DIR_EXISTS="true"
    DIR_PERMS=$(stat -c "%a" /home/ga/Documents/local_onion)
fi

# Check hostname file
HOSTNAME_EXISTS="false"
ONION_ADDRESS=""
if [ -f "/home/ga/Documents/local_onion/hostname" ]; then
    HOSTNAME_EXISTS="true"
    ONION_ADDRESS=$(cat /home/ga/Documents/local_onion/hostname | tr -d '\n' | tr -d '\r')
fi

# Check places.sqlite
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

python3 << PYEOF > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/${TASK_NAME}_places.sqlite"
onion_address = "$ONION_ADDRESS"

result = {
    "db_found": False,
    "onion_visited": False,
    "onion_bookmarked": False,
    "bookmark_title": ""
}

if not os.path.exists(db_path) or not onion_address:
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
        WHERE p.url LIKE ?
    """, ('%' + onion_address + '%',))
    if c.fetchone():
        result["onion_visited"] = True

    # Check bookmarks
    c.execute("""
        SELECT b.title, p.url
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        WHERE b.type=1 AND p.url LIKE ?
    """, ('%' + onion_address + '%',))
    row = c.fetchone()
    if row:
        result["onion_bookmarked"] = True
        result["bookmark_title"] = row["title"] or ""

    conn.close()
except Exception as e:
    pass

print(json.dumps(result))
PYEOF

python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db = json.load(f)
except:
    db = {}

db.update({
    "has_hidden_service_dir": $HAS_HIDDEN_SERVICE_DIR,
    "has_hidden_service_port": $HAS_HIDDEN_SERVICE_PORT,
    "dir_exists": $DIR_EXISTS,
    "dir_perms": "$DIR_PERMS",
    "hostname_exists": $HOSTNAME_EXISTS,
    "onion_address": "$ONION_ADDRESS"
})

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json