#!/bin/bash
# export_result.sh - Post-task hook for nist_cve_audit

echo "=== Exporting NIST CVE Audit Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to ensure database WAL is flushed
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read timestamps and paths
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Analyze Report File
REPORT_PATH="/home/ga/Documents/cve_audit_report.json"
REPORT_EXISTS=0
REPORT_FRESH=0
REPORT_CONTENT="{}"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH=1
    fi
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_PATH")
fi

# 5. Analyze Browser Data (Bookmarks & History)
HISTORY_VISITS=0
FOLDER_FOUND=0
BOOKMARK_COUNT=0
BOOKMARK_URLS=""

if [ -f "$PLACES_DB" ]; then
    # Force checkpoint to ensure we read latest data
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Use temp copy to avoid locks
    cp "$PLACES_DB" /tmp/places_export.sqlite
    
    # Check history for NVD visits
    HISTORY_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%nvd.nist.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check for 'Vulnerability Triage' folder
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Vulnerability Triage';" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        FOLDER_FOUND=1
        # Count bookmarks inside this folder
        BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
            
        # Get URLs of bookmarks in this folder
        BOOKMARK_URLS=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
             WHERE b.parent=$FOLDER_ID AND b.type=1;" 2>/dev/null | tr '\n' ',' || echo "")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 6. Create Result JSON
# Using python to safely construct JSON including the report content
python3 -c "
import json
import os

try:
    report_content = json.loads('''$REPORT_CONTENT''')
    report_valid = True
except:
    report_content = {}
    report_valid = False

result = {
    'task_start': $TASK_START,
    'report_exists': bool($REPORT_EXISTS),
    'report_fresh': bool($REPORT_FRESH),
    'report_valid_json': report_valid,
    'report_content': report_content,
    'history_visits': int($HISTORY_VISITS),
    'folder_found': bool($FOLDER_FOUND),
    'bookmark_count': int($BOOKMARK_COUNT),
    'bookmark_urls': '$BOOKMARK_URLS'.split(','),
    'screenshot_path': '/tmp/task_end.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"