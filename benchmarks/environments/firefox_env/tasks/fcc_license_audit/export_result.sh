#!/bin/bash
# export_result.sh - Post-task hook for FCC License Audit
set -e

echo "=== Exporting FCC License Audit results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to ensure places.sqlite WAL is flushed
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Gather environment variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)
PLACES_DB="$PROFILE_DIR/places.sqlite"
OUTPUT_FILE="/home/ga/Documents/fcc_license_audit.json"

# 4. Check JSON Output File
FILE_EXISTS=false
FILE_FRESH=false
FILE_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=true
    fi
    # Read content safely
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
fi

# 5. Analyze Firefox History & Bookmarks using Python
# We use Python here to robustly query SQLite and construct the final JSON result
python3 << EOF
import sqlite3
import json
import shutil
import os
import sys

# Setup paths
places_db = "$PLACES_DB"
temp_db = "/tmp/places_export.sqlite"
output_json = "/tmp/task_result.json"

results = {
    "history_found": False,
    "bookmark_folder_found": False,
    "bookmarks_in_folder": 0,
    "w1aw_bookmark_found": False,
    "w6yx_bookmark_found": False,
    "file_exists": $FILE_EXISTS, # python bool
    "file_fresh": $FILE_FRESH,   # python bool
    "file_content": {},          # placeholder
    "task_start_ts": $TASK_START
}

# Parse the user's output file content
try:
    raw_content = '''$FILE_CONTENT'''
    if raw_content.strip():
        results["file_content"] = json.loads(raw_content)
except Exception as e:
    print(f"Error parsing user JSON: {e}")
    results["json_error"] = str(e)

# Analyze Firefox Database
if os.path.exists(places_db):
    try:
        # Copy DB to avoid locks
        shutil.copy2(places_db, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()

        # 1. Check History for FCC ULS visits
        # wireless2.fcc.gov is the ULS search domain
        cursor.execute('''
            SELECT COUNT(*) FROM moz_historyvisits h
            JOIN moz_places p ON h.place_id = p.id
            WHERE p.url LIKE '%wireless2.fcc.gov%'
            AND h.visit_date > ?
        ''', ($TASK_START_US,))
        history_count = cursor.fetchone()[0]
        results["history_found"] = history_count > 0
        results["history_count"] = history_count

        # 2. Check for "FCC Audits" bookmark folder
        # Type 2 is a folder
        cursor.execute('''
            SELECT id FROM moz_bookmarks
            WHERE type = 2 AND title = 'FCC Audits'
        ''')
        folder_row = cursor.fetchone()

        if folder_row:
            results["bookmark_folder_found"] = True
            folder_id = folder_row[0]

            # 3. Count bookmarks in that folder
            cursor.execute('''
                SELECT count(*), p.url, b.title
                FROM moz_bookmarks b
                JOIN moz_places p ON b.fk = p.id
                WHERE b.parent = ? AND b.type = 1
            ''', (folder_id,))
            
            # Get list of URLs in folder
            cursor.execute('''
                SELECT p.url
                FROM moz_bookmarks b
                JOIN moz_places p ON b.fk = p.id
                WHERE b.parent = ? AND b.type = 1
            ''', (folder_id,))
            
            urls = [row[0] for row in cursor.fetchall()]
            results["bookmarks_in_folder"] = len(urls)
            results["bookmark_urls"] = urls

            # Simple string check for call signs or FRNs in URLs
            for url in urls:
                if '0002534816' in url or 'W1AW' in url.upper():
                    results["w1aw_bookmark_found"] = True
                if '0003507852' in url or 'W6YX' in url.upper():
                    results["w6yx_bookmark_found"] = True

        conn.close()
    except Exception as e:
        results["db_error"] = str(e)
        print(f"DB Error: {e}")

# Write result
with open(output_json, 'w') as f:
    json.dump(results, f, indent=2)

print("Export complete.")
EOF

# Cleanup
rm -f /tmp/places_export.sqlite

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="