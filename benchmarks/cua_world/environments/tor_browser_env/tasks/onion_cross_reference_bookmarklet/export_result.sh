#!/bin/bash
# export_result.sh for onion_cross_reference_bookmarklet
# Queries places.sqlite for bookmarks/history and prefs.js for UI state

echo "=== Exporting onion_cross_reference_bookmarklet results ==="

TASK_NAME="onion_cross_reference_bookmarklet"

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
        echo "Using profile: $PROFILE_DIR"
        break
    fi
done

# Check Toolbar visibility in prefs.js
TOOLBAR_VISIBLE="false"
PREFS_FILE="$PROFILE_DIR/prefs.js"
if [ -f "$PREFS_FILE" ]; then
    VISIBILITY=$(grep -oP 'user_pref\("browser\.toolbars\.bookmarks\.visibility",\s*"\K[^"]+' "$PREFS_FILE" 2>/dev/null || echo "newtab")
    if [ "$VISIBILITY" = "always" ]; then
        TOOLBAR_VISIBLE="true"
    fi
fi

# Copy DB to avoid WAL lock
PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Query places.sqlite via Python
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/onion_cross_reference_bookmarklet_places_export.sqlite"
report_path = "/home/ga/Documents/pivot_workflow_report.txt"

result = {
    "db_found": False,
    "bookmark_found": False,
    "bookmark_url": "",
    "bookmark_parent_is_toolbar": False,
    "history_urls": [],
    "report_exists": False,
    "report_content": ""
}

if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        with open(report_path, "r", encoding="utf-8") as f:
            result["report_content"] = f.read().strip()
    except:
        pass

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Look for the bookmark named "DDG Onion Pivot"
    c.execute("""
        SELECT b.id, b.title, p.url, b.parent, parent_b.title as parent_title
        FROM moz_bookmarks b
        LEFT JOIN moz_places p ON b.fk = p.id
        LEFT JOIN moz_bookmarks parent_b ON b.parent = parent_b.id
        WHERE b.type = 1 AND b.title = 'DDG Onion Pivot'
        ORDER BY b.dateAdded DESC LIMIT 1
    """)
    bm = c.fetchone()
    if bm:
        result["bookmark_found"] = True
        result["bookmark_url"] = bm["url"] or ""
        # The default Bookmarks Toolbar usually has title 'toolbar' or parent is specific
        if bm["parent_title"] and "toolbar" in bm["parent_title"].lower():
            result["bookmark_parent_is_toolbar"] = True

    # Get recent history
    c.execute("""
        SELECT p.url
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        ORDER BY h.visit_date DESC
        LIMIT 100
    """)
    history = [row["url"] for row in c.fetchall() if row["url"]]
    result["history_urls"] = history

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Merge shell vars into JSON
python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db = json.load(f)
except Exception:
    db = {}

db.update({
    "toolbar_visible": $TOOLBAR_VISIBLE,
    "task_start": $(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
})

with open('/tmp/task_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json