#!/bin/bash
# export_result.sh for configure_persistent_download_workflow
# Gathers system state, files, browser history, and preferences

echo "=== Exporting configure_persistent_download_workflow results ==="

TASK_NAME="configure_persistent_download_workflow"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

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

PLACES_DB="$PROFILE_DIR/places.sqlite"
PREFS_FILE="$PROFILE_DIR/prefs.js"

# Copy places DB to avoid lock issues
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Extract preferences
PREF_DOWNLOAD_DIR=""
PREF_FOLDER_LIST="-1"
PREF_USE_DOWNLOAD_DIR="unknown"

if [ -f "$PREFS_FILE" ]; then
    PREF_DOWNLOAD_DIR=$(grep -oP 'user_pref\("browser.download.dir",\s*"\K[^"]*' "$PREFS_FILE" 2>/dev/null || echo "")
    PREF_FOLDER_LIST=$(grep -oP 'user_pref\("browser.download.folderList",\s*\K[0-9]+' "$PREFS_FILE" 2>/dev/null || echo "-1")
    PREF_USE_DOWNLOAD_DIR=$(grep -oP 'user_pref\("browser.download.useDownloadDir",\s*\K(true|false)' "$PREFS_FILE" 2>/dev/null || echo "unknown")
fi

# Run python script to collect file metrics and DB info
python3 << PYEOF > /tmp/${TASK_NAME}_result.json
import os
import json
import sqlite3

result = {
    "task_start_ts": $TASK_START,
    "directory_exists": False,
    "files": {},
    "preferences": {
        "download_dir": "$PREF_DOWNLOAD_DIR",
        "folder_list": $PREF_FOLDER_LIST,
        "use_download_dir": "$PREF_USE_DOWNLOAD_DIR" == "true"
    },
    "history": {
        "check_torproject": False,
        "tb_manual": False,
        "spec_torproject": False
    }
}

download_dir = "/home/ga/Documents/SecureDownloads"
result["directory_exists"] = os.path.isdir(download_dir)

target_files = ["tor_check.html", "tor_manual.html", "tor_specs.html"]
for f in target_files:
    path = os.path.join(download_dir, f)
    exists = os.path.isfile(path)
    size = os.path.getsize(path) if exists else 0
    mtime = os.path.getmtime(path) if exists else 0
    
    is_html = False
    if exists and size > 1024:
        try:
            with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
                content = fp.read(4096).lower()
                if '<html' in content or '<!doctype' in content or '<body' in content:
                    is_html = True
        except:
            pass
            
    result["files"][f] = {
        "exists": exists,
        "size": size,
        "mtime": mtime,
        "is_html": is_html
    }

db_path = "$TEMP_DB"
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("""
            SELECT p.url FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
        """)
        urls = [row[0].lower() for row in c.fetchall()]
        
        for url in urls:
            if "check.torproject.org" in url:
                result["history"]["check_torproject"] = True
            if "tb-manual.torproject.org" in url:
                result["history"]["tb_manual"] = True
            if "spec.torproject.org" in url:
                result["history"]["spec_torproject"] = True
                
        conn.close()
    except Exception as e:
        result["db_error"] = str(e)

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json