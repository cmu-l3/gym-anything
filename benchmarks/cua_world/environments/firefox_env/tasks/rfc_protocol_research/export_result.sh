#!/bin/bash
# export_result.sh - Post-task hook for rfc_protocol_research

echo "=== Exporting rfc_protocol_research results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush WAL to main DB file
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Gather Paths and Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search if variable lost
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Check JSON Output File
JSON_FILE="/home/ga/Documents/rfc_reference.json"
JSON_EXISTS="false"
JSON_FRESH="false"
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH="true"
    fi
fi

# 5. Query Firefox DB (History & Bookmarks)
HISTORY_VISITS=0
RFC_FOLDER_EXISTS="false"
RFC_BOOKMARK_COUNT=0
CORRECT_URL_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Force WAL checkpoint to ensure data is in sqlite file
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy to temp to read safely
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History: Visits to rfc-editor or ietf datatracker
        HISTORY_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%rfc-editor.org%' OR p.url LIKE '%datatracker.ietf.org%') 
             AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        
        # Check Bookmark Folder "RFC Research"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE '%RFC Research%' LIMIT 1;" 2>/dev/null || echo "")
        
        if [ -n "$FOLDER_ID" ]; then
            RFC_FOLDER_EXISTS="true"
            
            # Count bookmarks inside this folder
            RFC_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=${FOLDER_ID};" 2>/dev/null || echo "0")
            
            # Count bookmarks in this folder that actually point to RFC sites
            CORRECT_URL_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=${FOLDER_ID} AND b.type=1 
                 AND (p.url LIKE '%rfc-editor.org%' OR p.url LIKE '%datatracker.ietf.org%' OR p.url LIKE '%ietf.org%');" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Create Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "json_exists": $JSON_EXISTS,
    "json_fresh": $JSON_FRESH,
    "history_visits": $HISTORY_VISITS,
    "rfc_folder_exists": $RFC_FOLDER_EXISTS,
    "rfc_bookmark_count": $RFC_BOOKMARK_COUNT,
    "rfc_correct_url_count": $CORRECT_URL_COUNT
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"