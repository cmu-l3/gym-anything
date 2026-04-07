#!/bin/bash
# export_result.sh - Post-task hook for configure_https_exception_for_legacy_site
echo "=== Exporting HTTPS-Only Exception task results ==="

TASK_NAME="configure_https_exception"

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# 2. Find Tor Browser profile
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

# 3. Copy DBs and prefs to /tmp to avoid WAL locks
if [ -n "$PROFILE_DIR" ]; then
    cp "$PROFILE_DIR/prefs.js" "/tmp/${TASK_NAME}_prefs.js" 2>/dev/null || true
    
    # Copy permissions DB + WAL files
    cp "$PROFILE_DIR/permissions.sqlite" "/tmp/${TASK_NAME}_permissions.sqlite" 2>/dev/null || true
    cp "$PROFILE_DIR/permissions.sqlite-wal" "/tmp/${TASK_NAME}_permissions.sqlite-wal" 2>/dev/null || true
    cp "$PROFILE_DIR/permissions.sqlite-shm" "/tmp/${TASK_NAME}_permissions.sqlite-shm" 2>/dev/null || true
    
    # Copy places DB + WAL files
    cp "$PROFILE_DIR/places.sqlite" "/tmp/${TASK_NAME}_places.sqlite" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-wal" "/tmp/${TASK_NAME}_places.sqlite-wal" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-shm" "/tmp/${TASK_NAME}_places.sqlite-shm" 2>/dev/null || true
fi

# 4. Use Python to parse SQLite and construct final JSON
python3 << 'PYEOF' > /tmp/task_result.json
import sqlite3
import json
import os

TASK_NAME = "configure_https_exception"
result = {
    "global_https_only_active": True,
    "exception_exists": False,
    "exception_permanent": False,
    "bookmark_exists": False,
    "bookmark_title_correct": False,
    "bookmark_url_http": False,
    "bookmark_url": ""
}

# Check Prefs.js for global disable
prefs_path = f"/tmp/{TASK_NAME}_prefs.js"
if os.path.exists(prefs_path):
    with open(prefs_path, 'r', encoding='utf-8') as f:
        content = f.read()
        if 'user_pref("dom.security.https_only_mode", false)' in content:
            result["global_https_only_active"] = False

# Check permissions.sqlite for the exception
perms_db = f"/tmp/{TASK_NAME}_permissions.sqlite"
if os.path.exists(perms_db):
    try:
        conn = sqlite3.connect(perms_db)
        c = conn.cursor()
        c.execute("SELECT origin, permission, expireType FROM moz_perms WHERE type='https-only-load-insecure' AND origin LIKE '%neverssl.com%'")
        rows = c.fetchall()
        for row in rows:
            if row[1] == 1:  # 1 = Allow
                result["exception_exists"] = True
                if row[2] == 0:  # 0 = Permanent
                    result["exception_permanent"] = True
        conn.close()
    except Exception as e:
        result["perms_db_error"] = str(e)

# Check places.sqlite for the bookmark
places_db = f"/tmp/{TASK_NAME}_places.sqlite"
if os.path.exists(places_db):
    try:
        conn = sqlite3.connect(places_db)
        c = conn.cursor()
        c.execute("SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.type=1 AND p.url LIKE '%neverssl.com%'")
        rows = c.fetchall()
        for row in rows:
            result["bookmark_exists"] = True
            result["bookmark_url"] = row[1]
            if row[0] == "Legacy Target":
                result["bookmark_title_correct"] = True
            if row[1] == "http://neverssl.com/":
                result["bookmark_url_http"] = True
        conn.close()
    except Exception as e:
        result["places_db_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json