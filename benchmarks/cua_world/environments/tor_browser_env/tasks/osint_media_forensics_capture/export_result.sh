#!/bin/bash
# export_result.sh for osint_media_forensics_capture task
# Extracts the final state: prefs.js, places.sqlite, and local files
set -e
echo "=== Exporting osint_media_forensics_capture task results ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")

# 2. Check Local File Evidence
EVIDENCE_FILE="/home/ga/Documents/evidence_media.jpg"
REPORT_FILE="/home/ga/Documents/forensic_metadata.txt"

EVIDENCE_EXISTS="false"
EVIDENCE_SIZE=0
EVIDENCE_IS_NEW="false"

if [ -f "$EVIDENCE_FILE" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_IS_NEW="true"
    fi
fi

REPORT_EXISTS="false"
REPORT_IS_NEW="false"
REPORT_CONTENT_B64=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_IS_NEW="true"
    fi
    # Use base64 to avoid JSON parsing issues with multiline/weird text
    REPORT_CONTENT_B64=$(base64 -w 0 "$REPORT_FILE" 2>/dev/null || echo "")
fi

# 3. Locate Tor Browser Profile
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

# 4. Check Security Slider Pref
SECURITY_SLIDER=1
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/prefs.js" ]; then
    VAL=$(grep "browser.security_level.security_slider" "$PROFILE_DIR/prefs.js" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "1")
    if [ -n "$VAL" ]; then
        SECURITY_SLIDER=$VAL
    fi
fi

# 5. Export SQLite Bookmarks safely
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/places_export.sqlite"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# 6. Build the JSON output using Python
python3 << 'PYEOF' > /tmp/task_result.json
import sqlite3
import json
import os

db_path = "/tmp/places_export.sqlite"
result = {
    "security_slider": int("$SECURITY_SLIDER"),
    "evidence_exists": "$EVIDENCE_EXISTS" == "true",
    "evidence_size": int("$EVIDENCE_SIZE"),
    "evidence_is_new": "$EVIDENCE_IS_NEW" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_is_new": "$REPORT_IS_NEW" == "true",
    "report_content_b64": "$REPORT_CONTENT_B64",
    "bookmark_found": False
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type=1")
        bookmarks = [{"title": r[0] or "", "url": r[1] or ""} for r in c.fetchall()]
        for bm in bookmarks:
            if bm["title"] == "OSINT Evidence Source" and "wikimedia.org" in bm["url"].lower():
                result["bookmark_found"] = True
                break
    except Exception as e:
        pass

with open('/tmp/final_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/final_result.json 2>/dev/null || true
echo "=== Final result generated ==="
cat /tmp/final_result.json