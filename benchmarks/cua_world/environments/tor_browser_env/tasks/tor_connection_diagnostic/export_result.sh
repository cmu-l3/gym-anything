#!/bin/bash
# export_result.sh for tor_connection_diagnostic task
# Exports file contents and browsing history for python verification

echo "=== Exporting tor_connection_diagnostic results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Find Tor Browser profile to read history
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

if [ -n "$PROFILE_DIR" ] && [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Use Python to safely read the text file, query SQLite, and generate the JSON result
python3 << PYEOF
import os
import json
import sqlite3

report_path = "/home/ga/Documents/tor_diagnostic_report.txt"
db_path = "/tmp/places_export.sqlite"

result = {
    "task_start": $TASK_START_TIMESTAMP,
    "report_exists": False,
    "report_mtime": 0,
    "report_size": 0,
    "report_content": "",
    "history_urls": []
}

# Check report file
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = os.path.getmtime(report_path)
    result["report_size"] = os.path.getsize(report_path)
    try:
        with open(report_path, 'r', encoding='utf-8', errors='replace') as f:
            result["report_content"] = f.read()
    except Exception as e:
        result["report_content"] = f"Error reading file: {e}"

# Check history
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("""
            SELECT p.url
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
        """)
        result["history_urls"] = [row[0] for row in c.fetchall()]
        conn.close()
    except Exception as e:
        result["db_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

# Cleanup
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json