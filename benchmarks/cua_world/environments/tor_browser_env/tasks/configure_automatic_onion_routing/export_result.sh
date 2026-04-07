#!/bin/bash
# export_result.sh for configure_automatic_onion_routing task
set -e

echo "=== Exporting task results ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

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

# 3. Check Prefs
PREFS_FILE="$PROFILE_DIR/prefs.js"
PRIORITIZE_ONIONS_ENABLED="false"
if [ -f "$PREFS_FILE" ] && grep -q 'user_pref("privacy.prioritizeonions.enabled", true);' "$PREFS_FILE"; then
    PRIORITIZE_ONIONS_ENABLED="true"
fi

# 4. Check Report File
REPORT_FILE="/home/ga/Documents/onion_routing_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTAINS_ONION="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Check for v3 onion address (56 lowercase letters/numbers 2-7 followed by .onion)
    if grep -qE '[a-z2-7]{56}\.onion' "$REPORT_FILE"; then
        REPORT_CONTAINS_ONION="true"
    fi
fi

# 5. Extract Bookmarks & History via Python to avoid bash escaping hell and handle WAL
TEMP_DB="/tmp/places_export.sqlite"
if [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-wal" ] && cp "$PROFILE_DIR/places.sqlite-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-shm" ] && cp "$PROFILE_DIR/places.sqlite-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

python3 << 'PYEOF' > /tmp/db_result.json
import sqlite3
import json
import os

db_path = "/tmp/places_export.sqlite"

result = {
    "folder_exists": False,
    "onion_bookmarked_in_folder": False,
    "history_has_onion_visit": False
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()

        # Check if folder exists
        c.execute("SELECT id FROM moz_bookmarks WHERE type=2 AND title='Auto-Routed Onions'")
        folder = c.fetchone()
        if folder:
            result["folder_exists"] = True
            folder_id = folder["id"]

            # Check for .onion bookmark inside the folder
            c.execute("""
                SELECT p.url FROM moz_bookmarks b
                JOIN moz_places p ON b.fk = p.id
                WHERE b.parent = ? AND p.url LIKE '%.onion%'
            """, (folder_id,))
            if c.fetchone():
                result["onion_bookmarked_in_folder"] = True

        # Check history for .onion visits
        c.execute("""
            SELECT p.url FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            WHERE p.url LIKE '%.onion%'
        """)
        if c.fetchone():
            result["history_has_onion_visit"] = True

        conn.close()
    except Exception as e:
        pass

print(json.dumps(result))
PYEOF

# Merge into final result file
python3 << PYEOF2
import json

try:
    with open('/tmp/db_result.json', 'r') as f:
        db_res = json.load(f)
except:
    db_res = {
        "folder_exists": False,
        "onion_bookmarked_in_folder": False,
        "history_has_onion_visit": False
    }

final_result = {
    "prioritizeonions_enabled": $PRIORITIZE_ONIONS_ENABLED,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_contains_onion": $REPORT_CONTAINS_ONION,
    "folder_exists": db_res["folder_exists"],
    "onion_bookmarked_in_folder": db_res["onion_bookmarked_in_folder"],
    "history_has_onion_visit": db_res["history_has_onion_visit"]
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
PYEOF2

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json