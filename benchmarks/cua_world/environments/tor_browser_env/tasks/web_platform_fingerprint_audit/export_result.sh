#!/bin/bash
# export_result.sh for web_platform_fingerprint_audit task
# Exports browsing history and target file stats

echo "=== Exporting web_platform_fingerprint_audit results ==="

TASK_NAME="web_platform_fingerprint_audit"
TASK_START_TIMESTAMP=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/tor-compatibility-report.txt"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile directory
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
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"

# Copy places.sqlite to avoid WAL lock issues
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Run python script to collect JSON result
python3 << PYEOF > /tmp/${TASK_NAME}_result.json
import sqlite3
import json
import os
import time

result = {
    "task": "$TASK_NAME",
    "task_start_ts": int("$TASK_START_TIMESTAMP"),
    "export_ts": int(time.time()),
    "db_found": False,
    "file_exists": False,
    "file_size": 0,
    "file_mtime": 0,
    "history_check_tor": False,
    "history_webrtc": False,
    "history_canvas": False,
    "history_eff": False
}

# Check file stats
report_path = "$REPORT_PATH"
if os.path.exists(report_path):
    result["file_exists"] = True
    stat = os.stat(report_path)
    result["file_size"] = stat.st_size
    result["file_mtime"] = stat.st_mtime

# Check browser history
db_path = "$TEMP_DB"
if os.path.exists(db_path):
    result["db_found"] = True
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("""
            SELECT p.url, MAX(h.visit_date) 
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            GROUP BY p.id
        """)
        for row in c.fetchall():
            url = str(row[0]).lower()
            if "check.torproject.org" in url:
                result["history_check_tor"] = True
            if "browserleaks.com/webrtc" in url:
                result["history_webrtc"] = True
            if "browserleaks.com/canvas" in url:
                result["history_canvas"] = True
            if "coveryourtracks.eff.org" in url:
                result["history_eff"] = True
        conn.close()
    except Exception as e:
        result["db_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Cleanup temp DB
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json