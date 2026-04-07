#!/bin/bash
echo "=== Exporting import_organize_research_bookmarks results ==="

TASK_NAME="import_organize_research_bookmarks"

# Capture final state screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Find profile and places.sqlite
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
TEMP_DB="/tmp/${TASK_NAME}_places_export.sqlite"

# Handle WAL-locked DB safely
if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Run Python logic to securely query SQLite DB state
python3 << PYEOF > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/${TASK_NAME}_places_export.sqlite"
# Firefox stores dates in microseconds
task_start = int("$TASK_START") * 1000000

result = {
    "db_found": False,
    "imported_folders": [],
    "imported_bookmarks": [],
    "all_folders": [],
    "censorship_research_folder": False,
    "pen_org_in_censorship": False,
    "pen_org_title_correct": False,
    "history_check_torproject": False,
    "history_archive_org": False,
    "history_pen_org": False,
    "bookmarks_created_after_start": False
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    # Query folder architecture
    c.execute("SELECT id, title, dateAdded FROM moz_bookmarks WHERE type=2 AND title IS NOT NULL")
    folders = c.fetchall()
    
    expected_imported_folders = ["Digital Archives", "Press Freedom Organizations", "Academic Resources", "Tor Network Resources"]
    
    for f in folders:
        title = f["title"]
        result["all_folders"].append(title)
        if title in expected_imported_folders:
            result["imported_folders"].append(title)
            if f["dateAdded"] >= task_start:
                result["bookmarks_created_after_start"] = True
        if title == "Censorship Research":
            result["censorship_research_folder"] = True
            if f["dateAdded"] >= task_start:
                result["bookmarks_created_after_start"] = True

    # Query bookmarks with their parent folder titles
    c.execute("""
        SELECT b.id, b.title, b.parent, p.url, bf.title as folder_title, b.dateAdded
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        LEFT JOIN moz_bookmarks bf ON b.parent = bf.id
        WHERE b.type=1
    """)
    bookmarks = c.fetchall()

    imported_urls = [
        "https://archive.org/", "https://web.archive.org/", "https://www.europeana.eu/",
        "https://rsf.org/", "https://cpj.org/", "https://www.eff.org/", "https://freedom.press/",
        "https://arxiv.org/", "https://scholar.google.com/", "https://doaj.org/",
        "https://www.torproject.org/", "https://check.torproject.org/", "https://support.torproject.org/"
    ]

    for b in bookmarks:
        url = b["url"]
        title = b["title"] or ""
        folder = b["folder_title"] or ""
        
        if any(i_url in url for i_url in imported_urls):
            result["imported_bookmarks"].append(url)
            
        if "pen.org" in url and folder == "Censorship Research":
            result["pen_org_in_censorship"] = True
            if title == "PEN America - Literary Freedom":
                result["pen_org_title_correct"] = True

    # Check browsing history ensuring post-task-start timestamps
    c.execute("""
        SELECT p.url, p.title, h.visit_date
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        WHERE h.visit_date >= ?
    """, (task_start,))
    
    history = c.fetchall()
    
    for h in history:
        url = h["url"].lower()
        if "check.torproject.org" in url:
            result["history_check_torproject"] = True
        elif "archive.org" in url:
            result["history_archive_org"] = True
        elif "pen.org" in url:
            result["history_pen_org"] = True

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="