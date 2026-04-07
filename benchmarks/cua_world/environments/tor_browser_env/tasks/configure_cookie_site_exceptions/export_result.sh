#!/bin/bash
set -e
echo "=== Exporting configure_cookie_site_exceptions results ==="

TASK_NAME="configure_cookie_site_exceptions"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile
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

if [ -n "$PROFILE_DIR" ]; then
    # Copy databases to temporary files to avoid WAL lock issues
    cp "$PROFILE_DIR/permissions.sqlite" "/tmp/${TASK_NAME}_perms.sqlite" 2>/dev/null || true
    cp "$PROFILE_DIR/permissions.sqlite-wal" "/tmp/${TASK_NAME}_perms.sqlite-wal" 2>/dev/null || true
    cp "$PROFILE_DIR/permissions.sqlite-shm" "/tmp/${TASK_NAME}_perms.sqlite-shm" 2>/dev/null || true
    
    cp "$PROFILE_DIR/places.sqlite" "/tmp/${TASK_NAME}_places.sqlite" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-wal" "/tmp/${TASK_NAME}_places.sqlite-wal" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-shm" "/tmp/${TASK_NAME}_places.sqlite-shm" 2>/dev/null || true
fi

# Use Python to gather info and save to JSON
python3 << PYEOF
import sqlite3
import json
import os

perms_db = "/tmp/${TASK_NAME}_perms.sqlite"
places_db = "/tmp/${TASK_NAME}_places.sqlite"
report_path = "/home/ga/Documents/cookie_policy_report.txt"

result = {
    "task_start": $TASK_START,
    "perms": [],
    "history": [],
    "report_exists": False,
    "report_mtime": 0,
    "report_content": ""
}

# 1. Query cookie exceptions
if os.path.exists(perms_db):
    try:
        conn = sqlite3.connect(perms_db)
        c = conn.cursor()
        c.execute("SELECT origin, permission FROM moz_perms WHERE type='cookie'")
        for row in c.fetchall():
            result["perms"].append({"origin": row[0], "permission": row[1]})
        conn.close()
    except Exception as e:
        result["perms_error"] = str(e)

# 2. Query browsing history
if os.path.exists(places_db):
    try:
        conn = sqlite3.connect(places_db)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places")
        for row in c.fetchall():
            result["history"].append(row[0])
        conn.close()
    except Exception as e:
        result["places_error"] = str(e)

# 3. Read policy report file
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    try:
        with open(report_path, "r", errors="ignore") as f:
            result["report_content"] = f.read(5000)
    except Exception as e:
        result["report_error"] = str(e)

# Write output json
output_json = "/tmp/${TASK_NAME}_result.json"
with open(output_json, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
echo "=== Export complete ==="
cat "/tmp/${TASK_NAME}_result.json"