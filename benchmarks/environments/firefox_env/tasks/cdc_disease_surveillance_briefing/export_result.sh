#!/bin/bash
# export_result.sh - Post-task hook for cdc_disease_surveillance_briefing

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush WAL (Write-Ahead Log) to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load configuration
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
# Convert to microseconds for Firefox history timestamp comparison
TASK_START_US=$((TASK_START * 1000000))

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Analyze Firefox Database (History & Bookmarks)
CDC_HISTORY_COUNT=0
WHO_HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
BOOKMARK_DOMAINS=""

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to read safely
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    # Force WAL checkpoint if possible (ignore errors)
    sqlite3 "$TEMP_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true

    if [ -f "$TEMP_DB" ]; then
        # History: CDC visits (distinct pages)
        CDC_HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
             WHERE p.url LIKE '%cdc.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # History: WHO visits
        WHO_HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
             WHERE p.url LIKE '%who.int%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        
        # Bookmarks: Check for "Disease Surveillance" folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Disease Surveillance' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS="true"
            # Count bookmarks in that folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=${FOLDER_ID};" 2>/dev/null || echo "0")
            
            # Get domains of bookmarks in that folder (for verification)
            BOOKMARK_DOMAINS=$(sqlite3 "$TEMP_DB" \
                "SELECT p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id \
                 WHERE b.type=1 AND b.parent=${FOLDER_ID};" 2>/dev/null | tr '\n' ',' || echo "")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Check Output File
OUTPUT_FILE="/home/ga/Documents/surveillance_briefing.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
    
    # Read content if valid JSON (safeguard against binary/garbage)
    if jq . "$OUTPUT_FILE" >/dev/null 2>&1; then
        FILE_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# 6. Create Result JSON
# We use Python to construct the final JSON to ensure proper escaping of the user's content
python3 -c "
import json
import os

try:
    content_str = '''$FILE_CONTENT'''
    if content_str.strip() == '{}':
        content_data = {}
    else:
        try:
            content_data = json.loads(content_str)
        except:
            content_data = {'error': 'invalid_json'}
            
    result = {
        'task_start': $TASK_START,
        'cdc_history_count': int('$CDC_HISTORY_COUNT'),
        'who_history_count': int('$WHO_HISTORY_COUNT'),
        'bookmark_folder_exists': '$BOOKMARK_FOLDER_EXISTS' == 'true',
        'bookmark_count': int('$BOOKMARK_COUNT'),
        'bookmark_domains': '$BOOKMARK_DOMAINS',
        'file_exists': '$FILE_EXISTS' == 'true',
        'file_fresh': '$FILE_FRESH' == 'true',
        'file_content': content_data
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
except Exception as e:
    print(f'Error creating result json: {e}')
"

echo "Export completed. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json