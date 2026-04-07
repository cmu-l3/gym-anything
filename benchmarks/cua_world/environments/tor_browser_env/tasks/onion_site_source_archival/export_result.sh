#!/bin/bash
echo "=== Exporting onion_site_source_archival results ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Collect bash variables
EVIDENCE_DIR="/home/ga/Documents/Evidence"
HTML_FILE="$EVIDENCE_DIR/ddg_search.html"
REPORT_FILE="$EVIDENCE_DIR/archive_report.txt"

# Profile dir for history query
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

# Safe copy of places.sqlite to query it while browser is running
TEMP_DB="/tmp/places_export.sqlite"
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null || true
    [ -f "$PROFILE_DIR/places.sqlite-wal" ] && cp "$PROFILE_DIR/places.sqlite-wal" "${TEMP_DB}-wal" 2>/dev/null || true
fi

# Run python script to analyze and output JSON safely
python3 << PYEOF
import os
import json
import sqlite3

task_start = int("$TASK_START")
evidence_dir = "$EVIDENCE_DIR"
html_file = "$HTML_FILE"
report_file = "$REPORT_FILE"
temp_db = "$TEMP_DB"

result = {
    "html_exists": False,
    "html_is_new": False,
    "html_size": 0,
    "html_has_content": False,
    "asset_dir_exists": False,
    "asset_dir_name": "",
    "js_file_count": 0,
    "report_exists": False,
    "report_is_new": False,
    "report_content": "",
    "history_has_search": False,
    "history_url": "",
    "task_start": task_start
}

# Verify HTML file
if os.path.isfile(html_file):
    result["html_exists"] = True
    mtime = os.path.getmtime(html_file)
    if mtime > task_start:
        result["html_is_new"] = True
    result["html_size"] = os.path.getsize(html_file)
    
    try:
        with open(html_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read().lower()
            if "digital forensics" in content:
                result["html_has_content"] = True
    except:
        pass

# Verify asset directory and JS file count
possible_asset_dirs = [d for d in os.listdir(evidence_dir) if os.path.isdir(os.path.join(evidence_dir, d))]
if possible_asset_dirs:
    # Prefer ddg_search_files if it exists, otherwise take what's there
    if "ddg_search_files" in possible_asset_dirs:
        asset_dir_name = "ddg_search_files"
    else:
        asset_dir_name = possible_asset_dirs[0]
        
    asset_dir_path = os.path.join(evidence_dir, asset_dir_name)
    result["asset_dir_exists"] = True
    result["asset_dir_name"] = asset_dir_name
    
    js_count = 0
    for root, _, files in os.walk(asset_dir_path):
        for file in files:
            if file.endswith('.js'):
                js_count += 1
    result["js_file_count"] = js_count

# Verify Report file
if os.path.isfile(report_file):
    result["report_exists"] = True
    if os.path.getmtime(report_file) > task_start:
        result["report_is_new"] = True
    try:
        with open(report_file, 'r', encoding='utf-8', errors='ignore') as f:
            result["report_content"] = f.read(2000) # Read up to 2KB for verification
    except:
        pass

# Check Browser History for verification
if os.path.isfile(temp_db):
    try:
        conn = sqlite3.connect(temp_db)
        c = conn.cursor()
        c.execute("""
            SELECT p.url
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            WHERE p.url LIKE '%duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion%'
            AND (p.url LIKE '%q=digital+forensics%' OR p.url LIKE '%q=digital%20forensics%')
            ORDER BY h.visit_date DESC
            LIMIT 1;
        """)
        row = c.fetchone()
        if row:
            result["history_has_search"] = True
            result["history_url"] = row[0]
        conn.close()
    except:
        pass

# Write out the payload for the verifier
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="