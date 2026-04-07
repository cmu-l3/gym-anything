#!/bin/bash
set -e
echo "=== Exporting configure_tor_bridges_workshop results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Find profile directory
export PROFILE_DIR=""
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

# Use Python to accurately parse state, database, and settings into JSON
python3 << 'PYEOF'
import os
import json
import sqlite3

profile_dir = os.environ.get('PROFILE_DIR', '')
temp_db = '/tmp/places_export.sqlite'
task_start_file = '/tmp/configure_tor_bridges_workshop_start_ts'

result = {
    'task_start_ts': 0,
    'bridge_enabled': False,
    'bridge_type': '',
    'history_bridges': False,
    'history_censorship': False,
    'bookmark_bridges': False,
    'bookmark_censorship': False,
    'file_exists': False,
    'file_size': 0,
    'file_mtime': 0,
    'file_content': ''
}

if os.path.exists(task_start_file):
    try:
        with open(task_start_file, 'r') as f:
            result['task_start_ts'] = int(f.read().strip())
    except:
        pass

# Parse Preferences and Torrc
if profile_dir:
    prefs_file = os.path.join(profile_dir, 'prefs.js')
    torrc_file = os.path.normpath(os.path.join(profile_dir, '../Tor/torrc'))
    
    if os.path.exists(prefs_file):
        with open(prefs_file, 'r', errors='ignore') as f:
            content = f.read()
            if '"torbrowser.settings.bridges.enabled", true' in content or '"extensions.torlauncher.use_bridges", true' in content:
                result['bridge_enabled'] = True
            if 'obfs4' in content.lower():
                result['bridge_type'] = 'obfs4'
                
    if os.path.exists(torrc_file):
        with open(torrc_file, 'r', errors='ignore') as f:
            content = f.read()
            if 'UseBridges 1' in content:
                result['bridge_enabled'] = True
            if 'obfs4' in content.lower():
                result['bridge_type'] = 'obfs4'

# Parse Places.sqlite database for history and bookmarks
if os.path.exists(temp_db):
    try:
        conn = sqlite3.connect(temp_db)
        c = conn.cursor()
        
        c.execute("SELECT url FROM moz_places p JOIN moz_historyvisits h ON p.id = h.place_id")
        for row in c.fetchall():
            url = row[0].lower() if row[0] else ''
            if "tb-manual.torproject.org/bridges" in url:
                result["history_bridges"] = True
            if "support.torproject.org/censorship" in url:
                result["history_censorship"] = True
                
        c.execute("SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type=1")
        for row in c.fetchall():
            title = row[0] or ""
            url = row[1].lower() if row[1] else ''
            if title == "Tor Bridge Guide - Workshop" and "tb-manual.torproject.org/bridges" in url:
                result["bookmark_bridges"] = True
            if title == "Censorship Circumvention Support" and "support.torproject.org/censorship" in url:
                result["bookmark_censorship"] = True
                
        conn.close()
    except Exception as e:
        print(f"Error reading sqlite: {e}")

# Parse the resulting markdown file
file_path = "/home/ga/Documents/bridge-workshop-guide.md"
if os.path.exists(file_path):
    result['file_exists'] = True
    result['file_size'] = os.path.getsize(file_path)
    result['file_mtime'] = os.path.getmtime(file_path)
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            result['file_content'] = f.read()
    except:
        pass

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/task_result.json