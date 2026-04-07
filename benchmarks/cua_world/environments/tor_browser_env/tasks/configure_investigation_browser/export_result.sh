#!/bin/bash
# export_result.sh - Post-task hook for configure_investigation_browser
# Aggregates sqlite db rows, prefs, and file statuses into JSON

echo "=== Exporting configure_investigation_browser results ==="

TASK_NAME="configure_investigation_browser"

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

# We will export DBs to temp files to avoid WAL read locks
cp "$PROFILE_DIR/permissions.sqlite" /tmp/perms_export.sqlite 2>/dev/null || true
[ -f "$PROFILE_DIR/permissions.sqlite-wal" ] && cp "$PROFILE_DIR/permissions.sqlite-wal" /tmp/perms_export.sqlite-wal 2>/dev/null || true
[ -f "$PROFILE_DIR/permissions.sqlite-shm" ] && cp "$PROFILE_DIR/permissions.sqlite-shm" /tmp/perms_export.sqlite-shm 2>/dev/null || true

cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite 2>/dev/null || true
[ -f "$PROFILE_DIR/places.sqlite-wal" ] && cp "$PROFILE_DIR/places.sqlite-wal" /tmp/places_export.sqlite-wal 2>/dev/null || true
[ -f "$PROFILE_DIR/places.sqlite-shm" ] && cp "$PROFILE_DIR/places.sqlite-shm" /tmp/places_export.sqlite-shm 2>/dev/null || true

PREFS_FILE="$PROFILE_DIR/prefs.js"

# Export report file data
REPORT_FILE="/home/ga/Documents/investigation_prep.txt"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_B64=""
if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    # Base64 encode the first 2KB for verification
    FILE_B64=$(head -c 2048 "$REPORT_FILE" | base64 -w 0)
fi

TASK_START_TS=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Use Python to read the exported DBs and prefs
cat << 'EOF' > /tmp/export_investigation_data.py
import sqlite3
import json
import os
import re

result = {
    "permissions": [],
    "history": [],
    "prefs": {
        "webnotifications_enabled": None,
        "startup_page": None,
        "startup_homepage": None
    }
}

# 1. Read Permissions
if os.path.exists('/tmp/perms_export.sqlite'):
    try:
        conn = sqlite3.connect('/tmp/perms_export.sqlite')
        c = conn.cursor()
        c.execute("SELECT origin, type, permission FROM moz_perms")
        result["permissions"] = [{"origin": r[0], "type": r[1], "permission": r[2]} for r in c.fetchall()]
        conn.close()
    except Exception as e:
        result["permissions_error"] = str(e)

# 2. Read History
if os.path.exists('/tmp/places_export.sqlite'):
    try:
        conn = sqlite3.connect('/tmp/places_export.sqlite')
        c = conn.cursor()
        c.execute("SELECT p.url FROM moz_places p JOIN moz_historyvisits h ON p.id = h.place_id")
        result["history"] = [r[0] for r in c.fetchall()]
        conn.close()
    except Exception as e:
        result["history_error"] = str(e)

# 3. Read Prefs
import sys
prefs_path = sys.argv[1] if len(sys.argv) > 1 else ""
if os.path.exists(prefs_path):
    with open(prefs_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        
        # dom.webnotifications.enabled
        match = re.search(r'user_pref\("dom\.webnotifications\.enabled",\s*(true|false)\);', content)
        if match: result["prefs"]["webnotifications_enabled"] = match.group(1)
        
        # browser.startup.page
        match = re.search(r'user_pref\("browser\.startup\.page",\s*(\d+)\);', content)
        if match: result["prefs"]["startup_page"] = match.group(1)
        
        # browser.startup.homepage
        match = re.search(r'user_pref\("browser\.startup\.homepage",\s*"([^"]+)"\);', content)
        if match: result["prefs"]["startup_homepage"] = match.group(1)

# Write out intermediate JSON
with open('/tmp/investigation_intermediate.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/export_investigation_data.py "$PREFS_FILE"

# Combine with bash variables into final JSON
python3 << EOF > /tmp/${TASK_NAME}_result.json
import json
with open('/tmp/investigation_intermediate.json', 'r') as f:
    data = json.load(f)

data["report_file"] = {
    "exists": "$FILE_EXISTS" == "true",
    "size": int("$FILE_SIZE"),
    "mtime": int("$FILE_MTIME"),
    "content_b64": "$FILE_B64"
}
data["task_start_ts"] = int("$TASK_START_TS")

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(data, f, indent=2)
EOF

# Clean up
rm -f /tmp/perms_export.sqlite* /tmp/places_export.sqlite* /tmp/export_investigation_data.py /tmp/investigation_intermediate.json

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json