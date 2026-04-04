#!/bin/bash
# export_result.sh - Post-task hook for nonprofit_financial_due_diligence

echo "=== Exporting nonprofit_financial_due_diligence results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Flush Firefox Database (Kill process)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Context Variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
# Convert to microseconds for Firefox history timestamp comparison
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Check ProPublica History
PROPUBLICA_VISITS=0
if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        PROPUBLICA_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%projects.propublica.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check bookmarks folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" "SELECT id FROM moz_bookmarks WHERE title='Grant Diligence' AND type=2 LIMIT 1;" 2>/dev/null || echo "")
        
        BOOKMARK_FOLDER_EXISTS="false"
        BOOKMARK_COUNT=0
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS="true"
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
            
            # Get URLs in the folder for validation
            BOOKMARKED_URLS=$(sqlite3 "$TEMP_DB" \
                "SELECT p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.parent=${FOLDER_ID} AND b.type=1;" 2>/dev/null || echo "")
        fi
        rm -f "$TEMP_DB"
    fi
fi

# 5. Check Files (PDF and JSON)
PDF_PATH="/home/ga/Documents/mozilla_990.pdf"
JSON_PATH="/home/ga/Documents/nonprofit_financials.json"

PDF_EXISTS="false"
PDF_FRESH="false"
PDF_SIZE=0

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_FRESH="true"
    fi
fi

JSON_EXISTS="false"
JSON_FRESH="false"
JSON_CONTENT="{}"

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH="true"
    fi
    # Read JSON content safely
    JSON_CONTENT=$(cat "$JSON_PATH" 2>/dev/null || echo "{}")
fi

# 6. Escape Content for JSON Export
# Basic escaping to ensure valid JSON nesting
SAFE_URLS=$(echo "$BOOKMARKED_URLS" | tr '\n' ',' | sed 's/,$//')

# 7. Create Result JSON
RESULT_FILE="/tmp/task_result.json"
# Use Python to create clean JSON to avoid shell string escaping issues
python3 -c "
import json
import os

try:
    json_content = json.loads('''$JSON_CONTENT''')
except:
    json_content = {}

result = {
    'propublica_visits': $PROPUBLICA_VISITS,
    'bookmark_folder_exists': $BOOKMARK_FOLDER_EXISTS,
    'bookmark_count': $BOOKMARK_COUNT,
    'bookmarked_urls': '$SAFE_URLS',
    'pdf_exists': $PDF_EXISTS,
    'pdf_fresh': $PDF_FRESH,
    'pdf_size': $PDF_SIZE,
    'json_exists': $JSON_EXISTS,
    'json_fresh': $JSON_FRESH,
    'json_content': json_content
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"

# 8. Set Permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="