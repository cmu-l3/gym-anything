#!/bin/bash
# export_result.sh - Post-task hook for grants_gov_search

echo "=== Exporting grants_gov_search results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush database WAL (Write Ahead Log)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Retrieve setup info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Analyze Browser State (History & Bookmarks)
PLACES_DB="$PROFILE_DIR/places.sqlite"
GRANTS_GOV_VISITS=0
FOLDER_EXISTS=0
BOOKMARK_COUNT=0
VALID_BOOKMARKS=0

if [ -f "$PLACES_DB" ]; then
    # Force checkpoint to ensure data is in main DB file
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check history for grants.gov visits
        GRANTS_GOV_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%grants.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check for 'Grant Prospects' folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Grant Prospects' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS=1
            # Count bookmarks in that folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
            
            # Check if they are actually grants.gov links
            VALID_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=${FOLDER_ID} AND b.type=1 AND p.url LIKE '%grants.gov%';" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Analyze Output File
OUTPUT_FILE="/home/ga/Documents/grant_prospects.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "grants_gov_visits": $GRANTS_GOV_VISITS,
    "bookmark_folder_exists": $FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "valid_bookmarks_count": $VALID_BOOKMARKS,
    "output_file_exists": $FILE_EXISTS,
    "output_file_fresh": $FILE_FRESH,
    "output_file_size": $FILE_SIZE
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json