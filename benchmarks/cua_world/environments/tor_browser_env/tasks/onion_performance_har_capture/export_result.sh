#!/bin/bash
# export_result.sh for onion_performance_har_capture task
# Checks for HAR file and browsing history

echo "=== Exporting onion_performance_har_capture results ==="

TASK_NAME="onion_performance_har_capture"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/onion_performance_baseline.har"

# Check if file exists and properties
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
echo "Target file exists: $FILE_EXISTS (new: $FILE_IS_NEW, size: ${FILE_SIZE}B)"

# Find Tor Browser profile to check places.sqlite history
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

# Copy database to safely read without WAL lock
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Query history
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/onion_performance_har_capture_places.sqlite"
result = {
    "history_has_target_query": False,
    "history_has_onion_domain": False
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        c.execute("""
            SELECT p.url
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            ORDER BY h.visit_date DESC
            LIMIT 100
        """)
        urls = [row["url"].lower() for row in c.fetchall() if row["url"]]
        
        for url in urls:
            if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url:
                result["history_has_onion_domain"] = True
            if "tor_network_perf_audit_9921" in url:
                result["history_has_target_query"] = True
                
        conn.close()
    except Exception as e:
        pass

print(json.dumps(result))
PYEOF

# Check if browser is running
TOR_RUNNING="false"
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null && TOR_RUNNING="true"

# Merge and dump final JSON
python3 << PYEOF2
import json
import os

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db = json.load(f)
except Exception:
    db = {"history_has_target_query": False, "history_has_onion_domain": False}

db.update({
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "task_start": $TASK_START,
    "tor_browser_running": $TOR_RUNNING
})

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json