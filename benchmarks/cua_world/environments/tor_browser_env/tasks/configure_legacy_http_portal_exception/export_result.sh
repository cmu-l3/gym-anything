#!/bin/bash
# export_result.sh for configure_legacy_http_portal_exception
# Queries permissions and places DBs and exports verification data

echo "=== Exporting configure_legacy_http_portal_exception results ==="

TASK_NAME="configure_legacy_http_portal_exception"

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
    # Copy DBs to avoid WAL locking issues
    cp "$PROFILE_DIR/permissions.sqlite" "/tmp/perms.sqlite" 2>/dev/null || true
    cp "$PROFILE_DIR/permissions.sqlite-wal" "/tmp/perms.sqlite-wal" 2>/dev/null || true
    cp "$PROFILE_DIR/permissions.sqlite-shm" "/tmp/perms.sqlite-shm" 2>/dev/null || true
    
    cp "$PROFILE_DIR/places.sqlite" "/tmp/places.sqlite" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-wal" "/tmp/places.sqlite-wal" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-shm" "/tmp/places.sqlite-shm" 2>/dev/null || true
fi

# Run Python script to assemble the exact state payload
python3 << 'PYEOF'
import sqlite3
import json
import os

result = {
    "exception_exists": False,
    "permission": -1,
    "expire_type": -1,
    "history_visited": False,
    "evidence_file_exists": False,
    "evidence_file_new": False,
    "evidence_contains_keyword": False,
}

# 1. Check permissions.sqlite for the HTTPS-Only exception
if os.path.exists("/tmp/perms.sqlite"):
    try:
        conn = sqlite3.connect("/tmp/perms.sqlite")
        c = conn.cursor()
        # Find origin like neverssl.com with the HTTPS-only bypass permission
        c.execute("SELECT permission, expireType FROM moz_perms WHERE type='https-only-load-insecure' AND origin LIKE '%neverssl.com%'")
        row = c.fetchone()
        if row:
            result["exception_exists"] = True
            result["permission"] = row[0]
            result["expire_type"] = row[1]
    except Exception as e:
        result["error_perms"] = str(e)

# 2. Check places.sqlite for the visit to neverssl
if os.path.exists("/tmp/places.sqlite"):
    try:
        conn = sqlite3.connect("/tmp/places.sqlite")
        c = conn.cursor()
        c.execute("SELECT 1 FROM moz_places p JOIN moz_historyvisits h ON p.id = h.place_id WHERE p.url LIKE '%neverssl.com%'")
        if c.fetchone():
            result["history_visited"] = True
    except Exception as e:
        result["error_places"] = str(e)

# 3. Check Evidence file
ev_path = "/home/ga/Documents/neverssl_evidence.txt"
if os.path.exists(ev_path):
    result["evidence_file_exists"] = True
    
    try:
        with open("/tmp/configure_legacy_http_portal_exception_start_ts", "r") as f:
            start_ts = int(f.read().strip())
        if os.path.getmtime(ev_path) > start_ts:
            result["evidence_file_new"] = True
    except:
        pass
        
    try:
        with open(ev_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read().lower()
            if "neverssl" in content:
                result["evidence_contains_keyword"] = True
    except:
        pass

with open("/tmp/configure_legacy_http_portal_exception_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Cleanup temp databases
rm -f /tmp/perms.sqlite* /tmp/places.sqlite* 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json