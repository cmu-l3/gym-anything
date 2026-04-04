#!/bin/bash
# export_result.sh - Post-task hook for veterinary_toxicology_triage

echo "=== Exporting Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 3. Force Flush Firefox DB (Kill process)
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# 4. Analyze Firefox Data (History & Bookmarks)
ASPCA_HISTORY_COUNT=0
VET_FOLDER_EXISTS=0
VET_BOOKMARK_COUNT=0
BOOKMARK_TITLES=""

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite
    
    # Check History for aspca.org visits AFTER task start
    ASPCA_HISTORY_COUNT=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%aspca.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check for 'Vet Tox Resources' folder (case insensitive)
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%vet tox resources%';" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        VET_FOLDER_EXISTS=1
        # Count bookmarks in that folder
        VET_BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        
        # Get bookmark URLs for debugging
        BOOKMARK_TITLES=$(sqlite3 /tmp/places_export.sqlite \
             "SELECT title FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null | tr '\n' '|')
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 5. Analyze Output File
REPORT_FILE="/home/ga/Documents/feline_triage_report.json"
REPORT_EXISTS=0
REPORT_FRESH=0
REPORT_CONTENT="{}"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH=1
    fi
    
    # Read content safely (cat directly)
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# 6. Create JSON Result
# Use python to safely construct JSON to avoid escaping issues
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'aspca_history_count': $ASPCA_HISTORY_COUNT,
    'vet_folder_exists': bool($VET_FOLDER_EXISTS),
    'vet_bookmark_count': $VET_BOOKMARK_COUNT,
    'bookmark_titles': '$BOOKMARK_TITLES',
    'report_exists': bool($REPORT_EXISTS),
    'report_fresh': bool($REPORT_FRESH),
    'screenshot_path': '/tmp/task_final.png'
}

# Try to parse the user's report file to ensure it's valid JSON
report_content_raw = '''$REPORT_CONTENT'''
try:
    if result['report_exists']:
        # We read the file directly in python to handle quotes better than bash var passing
        with open('$REPORT_FILE', 'r') as f:
            result['report_data'] = json.load(f)
        result['report_valid_json'] = True
    else:
        result['report_data'] = {}
        result['report_valid_json'] = False
except Exception as e:
    result['report_data'] = {}
    result['report_valid_json'] = False
    result['json_error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="