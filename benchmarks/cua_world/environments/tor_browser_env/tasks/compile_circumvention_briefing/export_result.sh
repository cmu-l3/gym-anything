#!/bin/bash
# export_result.sh for compile_circumvention_briefing
# Checks Markdown contents, PDF validity, and browser history

echo "=== Exporting compile_circumvention_briefing results ==="

TASK_NAME="compile_circumvention_briefing"

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# 2. Find Tor Browser profile for history extraction
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

# 3. Use Python to gather all results into a single JSON
python3 << 'PYEOF'
import sqlite3
import json
import os
import time

task_name = "compile_circumvention_briefing"
db_path = f"/tmp/{task_name}_places.sqlite"
md_path = "/home/ga/Documents/Briefing/Transports_Summary.md"
pdf_path = "/home/ga/Documents/Briefing/Circumvention_Manual.pdf"

# Load task start time
start_ts = 0
try:
    with open(f"/tmp/{task_name}_start_ts", "r") as f:
        start_ts = int(f.read().strip())
except:
    pass

result = {
    "task_start_ts": start_ts,
    "export_ts": int(time.time()),
    "md_exists": False,
    "md_is_new": False,
    "md_content": "",
    "pdf_exists": False,
    "pdf_is_new": False,
    "pdf_size": 0,
    "pdf_magic_valid": False,
    "history_urls": []
}

# --- Check Markdown File ---
if os.path.exists(md_path):
    result["md_exists"] = True
    mtime = os.path.getmtime(md_path)
    if mtime >= start_ts:
        result["md_is_new"] = True
    
    try:
        with open(md_path, "r", encoding="utf-8") as f:
            # Read up to 10KB to prevent massive file issues
            result["md_content"] = f.read(10240)
    except Exception as e:
        result["md_content"] = f"Error reading file: {str(e)}"

# --- Check PDF File ---
if os.path.exists(pdf_path):
    result["pdf_exists"] = True
    mtime = os.path.getmtime(pdf_path)
    if mtime >= start_ts:
        result["pdf_is_new"] = True
    
    result["pdf_size"] = os.path.getsize(pdf_path)
    
    # Check magic bytes for PDF (%PDF)
    try:
        with open(pdf_path, "rb") as f:
            header = f.read(4)
            if header == b"%PDF":
                result["pdf_magic_valid"] = True
    except:
        pass

# --- Check History ---
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        c.execute("""
            SELECT p.url, MAX(h.visit_date) as last_visit
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            GROUP BY p.id
            ORDER BY last_visit DESC
            LIMIT 200
        """)
        
        for row in c.fetchall():
            url = row["url"]
            if url:
                result["history_urls"].append(url.lower())
                
        conn.close()
    except Exception as e:
        result["history_error"] = str(e)

# Write output JSON
out_path = f"/tmp/{task_name}_result.json"
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

print(f"Results written to {out_path}")
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json