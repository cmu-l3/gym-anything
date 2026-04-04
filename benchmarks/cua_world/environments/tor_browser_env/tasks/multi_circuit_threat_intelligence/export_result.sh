#!/bin/bash
# export_result.sh for multi_circuit_threat_intelligence task

echo "=== Exporting multi_circuit_threat_intelligence results ==="

TASK_NAME="multi_circuit_threat_intelligence"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Check file 1: ransomware_research_notes.txt
FILE1="/home/ga/Documents/ransomware_research_notes.txt"
FILE1_EXISTS="false"
FILE1_IS_NEW="false"
FILE1_SIZE=0
if [ -f "$FILE1" ]; then
    FILE1_EXISTS="true"
    FILE1_MTIME=$(stat -c %Y "$FILE1" 2>/dev/null || echo "0")
    [ "$FILE1_MTIME" -gt "$TASK_START" ] && FILE1_IS_NEW="true"
    FILE1_SIZE=$(stat -c %s "$FILE1" 2>/dev/null || echo "0")
fi
echo "File1 (ransomware_research_notes.txt): exists=$FILE1_EXISTS, new=$FILE1_IS_NEW, size=$FILE1_SIZE"

# Check file 2: phishing_research_notes.txt
FILE2="/home/ga/Documents/phishing_research_notes.txt"
FILE2_EXISTS="false"
FILE2_IS_NEW="false"
FILE2_SIZE=0
if [ -f "$FILE2" ]; then
    FILE2_EXISTS="true"
    FILE2_MTIME=$(stat -c %Y "$FILE2" 2>/dev/null || echo "0")
    [ "$FILE2_MTIME" -gt "$TASK_START" ] && FILE2_IS_NEW="true"
    FILE2_SIZE=$(stat -c %s "$FILE2" 2>/dev/null || echo "0")
fi
echo "File2 (phishing_research_notes.txt): exists=$FILE2_EXISTS, new=$FILE2_IS_NEW, size=$FILE2_SIZE"

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
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Query bookmarks and history
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/multi_circuit_threat_intelligence_places.sqlite"

result = {
    "db_found": False,
    "folder_ransomware": False,
    "folder_phishing": False,
    "bookmark_in_ransomware_folder": False,
    "bookmark_in_phishing_folder": False,
    "history_has_check_torproject": False,
    "check_torproject_visit_count": 0,
    "history_has_ddg_onion": False,
    "history_has_ddg_ransomware_search": False,
    "history_has_ddg_phishing_search": False,
    "all_folders": []
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Get all bookmark folders
    c.execute("""
        SELECT id, title FROM moz_bookmarks
        WHERE type=2 AND title IS NOT NULL AND title != ''
        ORDER BY dateAdded DESC
    """)
    folders = [{"id": row["id"], "title": row["title"]} for row in c.fetchall()]
    result["all_folders"] = [f["title"] for f in folders]

    folder_map = {f["title"]: f["id"] for f in folders}
    result["folder_ransomware"] = "Threat Intel - Ransomware" in folder_map
    result["folder_phishing"] = "Threat Intel - Phishing" in folder_map

    # Check bookmarks in specific folders
    c.execute("""
        SELECT b.title, p.url, bf.title as folder_title
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        LEFT JOIN moz_bookmarks bf ON b.parent = bf.id
        WHERE b.type=1
    """)
    for row in c.fetchall():
        folder = row["folder_title"] or ""
        if folder == "Threat Intel - Ransomware":
            result["bookmark_in_ransomware_folder"] = True
        if folder == "Threat Intel - Phishing":
            result["bookmark_in_phishing_folder"] = True

    # Check history
    c.execute("""
        SELECT p.url, COUNT(*) as visit_count
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        GROUP BY p.id
        ORDER BY MAX(h.visit_date) DESC
        LIMIT 200
    """)
    history = [(row["url"] or "").lower() for row in c.fetchall()]
    visit_counts = {}
    c.execute("""
        SELECT p.url, COUNT(*) as cnt
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        GROUP BY p.id
    """)
    for row in c.fetchall():
        url = (row["url"] or "").lower()
        visit_counts[url] = row["cnt"]

    for url in history:
        if "check.torproject.org" in url:
            result["history_has_check_torproject"] = True
        if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url:
            result["history_has_ddg_onion"] = True
        if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url and "ransomware" in url:
            result["history_has_ddg_ransomware_search"] = True
        if "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in url and "phishing" in url:
            result["history_has_ddg_phishing_search"] = True

    # Count check.torproject.org visits (2+ means New Identity was used)
    for url, cnt in visit_counts.items():
        if "check.torproject.org" in url:
            result["check_torproject_visit_count"] = cnt

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

TOR_RUNNING="false"
DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null && TOR_RUNNING="true"

python3 << PYEOF2
import json

db = json.load(open('/tmp/${TASK_NAME}_db_result.json'))
db.update({
    "file1_exists": $FILE1_EXISTS,
    "file1_is_new": $FILE1_IS_NEW,
    "file1_size": $FILE1_SIZE,
    "file2_exists": $FILE2_EXISTS,
    "file2_is_new": $FILE2_IS_NEW,
    "file2_size": $FILE2_SIZE,
    "task_start": $TASK_START,
    "tor_browser_running": $TOR_RUNNING
})
with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(db, f, indent=2)
print("Result written")
PYEOF2

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json
