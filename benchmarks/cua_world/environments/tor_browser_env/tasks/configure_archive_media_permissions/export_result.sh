#!/bin/bash
echo "=== Exporting configure_archive_media_permissions results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Find profile directory
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
    # Copy profile files locally for safe SQLite querying without locking the live browser DBs
    cp "$PROFILE_DIR/prefs.js" /tmp/prefs_export.js 2>/dev/null || true
    cp "$PROFILE_DIR/permissions.sqlite" /tmp/perms_export.sqlite 2>/dev/null || true
    [ -f "$PROFILE_DIR/permissions.sqlite-wal" ] && cp "$PROFILE_DIR/permissions.sqlite-wal" /tmp/perms_export.sqlite-wal 2>/dev/null || true
    [ -f "$PROFILE_DIR/permissions.sqlite-shm" ] && cp "$PROFILE_DIR/permissions.sqlite-shm" /tmp/perms_export.sqlite-shm 2>/dev/null || true
    
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-wal" ] && cp "$PROFILE_DIR/places.sqlite-wal" /tmp/places_export.sqlite-wal 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-shm" ] && cp "$PROFILE_DIR/places.sqlite-shm" /tmp/places_export.sqlite-shm 2>/dev/null || true
fi

# Run python script to extract task metrics from copied sqlite databases
python3 << 'PYEOF' > /tmp/task_result.json
import sqlite3
import json
import os

db_perms = "/tmp/perms_export.sqlite"
db_places = "/tmp/places_export.sqlite"
prefs_file = "/tmp/prefs_export.js"

result = {
    "autoplay_default": -1,
    "wikimedia_allowed": False,
    "archive_allowed": False,
    "folder_exists": False,
    "folder_id": -1,
    "wikimedia_bookmarked": False,
    "archive_bookmarked": False
}

# 1. Read prefs.js for global Autoplay default
if os.path.exists(prefs_file):
    with open(prefs_file, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            if 'user_pref("media.autoplay.default"' in line:
                try:
                    val = int(line.split(',')[1].strip().split(')')[0])
                    result['autoplay_default'] = val
                except:
                    pass

# 2. Read permissions.sqlite for Site Exceptions
if os.path.exists(db_perms):
    try:
        conn = sqlite3.connect(db_perms)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        c.execute("SELECT origin, type, permission FROM moz_perms WHERE type='autoplay-media'")
        for row in c.fetchall():
            origin = row['origin'] or ''
            perm = row['permission']
            # permission 1 represents "Allow" in Mozilla browsers
            if 'commons.wikimedia.org' in origin and perm == 1:
                result['wikimedia_allowed'] = True
            if 'archive.org' in origin and perm == 1:
                result['archive_allowed'] = True
                
        conn.close()
    except Exception as e:
        result['perms_error'] = str(e)

# 3. Read places.sqlite for Bookmarks
if os.path.exists(db_places):
    try:
        conn = sqlite3.connect(db_places)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        # Check if the Trusted Archives folder exists
        c.execute("SELECT id FROM moz_bookmarks WHERE type=2 AND title='Trusted Archives'")
        folder = c.fetchone()
        if folder:
            result['folder_exists'] = True
            folder_id = folder['id']
            result['folder_id'] = folder_id
            
            # Check the children of that folder
            c.execute("SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.parent=?", (folder_id,))
            for row in c.fetchall():
                url = row['url'] or ''
                title = row['title'] or ''
                if 'commons.wikimedia.org' in url and title == 'Wikimedia Commons':
                    result['wikimedia_bookmarked'] = True
                if 'archive.org' in url and title == 'Internet Archive':
                    result['archive_bookmarked'] = True
                    
        conn.close()
    except Exception as e:
        result['places_error'] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="