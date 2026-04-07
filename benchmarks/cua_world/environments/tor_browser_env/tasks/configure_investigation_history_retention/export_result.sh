#!/bin/bash
# export_result.sh - Post-task hook for configure_investigation_history_retention

echo "=== Exporting configure_investigation_history_retention task results ==="

TASK_NAME="configure_investigation_history_retention"
TASK_START_TS=$(cat "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Locate Tor Browser profile
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

# 3. Check if Tor Browser is still running
TOR_RUNNING="false"
if pgrep -u ga -f "firefox.*TorBrowser" > /dev/null; then
    TOR_RUNNING="true"
    echo "Warning: Tor Browser is still running. History might not be fully flushed to disk."
fi

# 4. Copy databases to safe temp location to avoid SQLite locking issues
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/places_export.sqlite"
PREFS_FILE="$PROFILE_DIR/prefs.js"

DB_EXISTS="false"
if [ -f "$PLACES_DB" ]; then
    DB_EXISTS="true"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# 5. Extract verification data using Python
python3 << PYEOF > "/tmp/${TASK_NAME}_result.json"
import os
import json
import sqlite3

result = {
    "task_start_ts": ${TASK_START_TS},
    "tor_running_at_end": ${TOR_RUNNING},
    "db_exists": ${DB_EXISTS},
    "pb_autostart_disabled": False,
    "sanitize_on_shutdown_disabled": False,
    "visited_check_torproject": False,
    "visited_duckduckgo": False,
    "history_urls": []
}

# Parse prefs.js
prefs_path = "${PREFS_FILE}"
if os.path.exists(prefs_path):
    with open(prefs_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        # In Tor Browser, default is true. If agent disabled it, it writes 'false'
        if 'user_pref("browser.privatebrowsing.autostart", false);' in content:
            result["pb_autostart_disabled"] = True
        if 'user_pref("privacy.sanitize.sanitizeOnShutdown", false);' in content:
            result["sanitize_on_shutdown_disabled"] = True

# Parse places.sqlite
db_path = "${TEMP_DB}"
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        # Get URLs visited AFTER task start
        # Firefox stores visit_date in microseconds since epoch
        query = f"""
            SELECT p.url, h.visit_date 
            FROM moz_places p 
            JOIN moz_historyvisits h ON p.id = h.place_id
            WHERE (h.visit_date / 1000000) > {result['task_start_ts']}
        """
        c.execute(query)
        rows = c.fetchall()
        
        for row in rows:
            url = row[0].lower()
            result["history_urls"].append(url)
            if "check.torproject.org" in url:
                result["visited_check_torproject"] = True
            if "duckduckgo.com" in url:
                result["visited_duckduckgo"] = True
                
    except Exception as e:
        result["db_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json