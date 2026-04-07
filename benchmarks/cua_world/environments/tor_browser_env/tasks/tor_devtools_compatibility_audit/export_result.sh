#!/bin/bash
set -e
echo "=== Exporting tor_devtools_compatibility_audit results ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/tor_compatibility_report.txt"

# 2. Check output file metadata
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# 3. Check Browser History
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
TEMP_DB="/tmp/places_export.sqlite"

if [ -f "$PLACES_DB" ]; then
    # Copy DB to avoid lock issues with running browser
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# 4. Generate JSON export with Python sqlite3 query
python3 << PYEOF > /tmp/task_result.json
import sqlite3
import json
import os

db_path = "/tmp/places_export.sqlite"
result = {
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size": $FILE_SIZE,
    "history_check": False,
    "history_download": False,
    "history_eff": False
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("""
            SELECT p.url 
            FROM moz_places p 
            JOIN moz_historyvisits h ON p.id = h.place_id
        """)
        for row in c.fetchall():
            url = row[0].lower()
            if "check.torproject.org" in url:
                result["history_check"] = True
            if "torproject.org/download" in url:
                result["history_download"] = True
            if "eff.org" in url:
                result["history_eff"] = True
    except Exception as e:
        result["db_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="