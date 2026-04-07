#!/bin/bash
# export_result.sh - Post-task hook for tor_circuit_rotation_report
# Exports file contents and browser history for verification

echo "=== Exporting tor_circuit_rotation_report results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/circuit_report.txt"

# Check report file existence and metadata
FILE_EXISTS="false"
FILE_MTIME=0
FILE_SIZE=0
FILE_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Safely read content (first 4KB to avoid huge files)
    FILE_CONTENT=$(head -c 4096 "$REPORT_PATH" | tr -d '\000-\011\013-\037' | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n')
fi

# Find Tor Browser profile and query history/bookmarks
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

TEMP_DB="/tmp/places_export.sqlite"
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-wal" ] && cp "$PROFILE_DIR/places.sqlite-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-shm" ] && cp "$PROFILE_DIR/places.sqlite-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Run Python script to securely query the DB and produce JSON
python3 << PYEOF > /tmp/task_result.json
import sqlite3
import json
import os
import re

db_path = "/tmp/places_export.sqlite"
result = {
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "file_size": $FILE_SIZE,
    "task_start_time": $TASK_START,
    "file_content": "$FILE_CONTENT",
    "db_found": False,
    "history_check_torproject": False,
    "history_check_torproject_visits": 0,
    "history_www_torproject": False,
    "bookmark_tor_verifier_exists": False
}

if os.path.exists(db_path):
    result["db_found"] = True
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()

        # Check history for check.torproject.org and count visits
        c.execute("""
            SELECT p.url, COUNT(h.id) as visits 
            FROM moz_places p 
            JOIN moz_historyvisits h ON p.id = h.place_id 
            WHERE p.url LIKE '%check.torproject.org%'
            GROUP BY p.id
        """)
        for row in c.fetchall():
            result["history_check_torproject"] = True
            result["history_check_torproject_visits"] += row["visits"]

        # Check history for www.torproject.org
        c.execute("""
            SELECT p.url FROM moz_places p 
            JOIN moz_historyvisits h ON p.id = h.place_id 
            WHERE p.url LIKE '%www.torproject.org%'
            LIMIT 1
        """)
        if c.fetchone():
            result["history_www_torproject"] = True

        # Check bookmarks
        c.execute("""
            SELECT b.title, p.url 
            FROM moz_bookmarks b 
            JOIN moz_places p ON b.fk = p.id 
            WHERE b.type = 1
        """)
        for row in c.fetchall():
            title = row["title"] or ""
            url = row["url"] or ""
            if "check.torproject.org" in url and "Tor Connection Verifier" in title:
                result["bookmark_tor_verifier_exists"] = True

        conn.close()
    except Exception as e:
        result["db_error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB"* 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json