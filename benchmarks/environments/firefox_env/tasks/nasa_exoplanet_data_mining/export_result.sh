#!/bin/bash
# export_result.sh - Post-task hook for nasa_exoplanet_data_mining

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to ensure database is flushed (WAL checkpoint)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Get timing info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 4. Locate Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback logic
    for candidate in \
        "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
        "/home/ga/.mozilla/firefox/default.profile"; do
        if [ -f "$candidate/places.sqlite" ]; then
            PROFILE_DIR="$candidate"
            break
        fi
    done
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 5. Analyze Browser History & Bookmarks
ARCHIVE_VISITS=0
BOOKMARK_FOLDER_EXISTS=0
ARCHIVE_BOOKMARK_EXISTS=0

if [ -f "$PLACES_DB" ]; then
    # Force checkpoint
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Use temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check history for NASA Exoplanet Archive
        ARCHIVE_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%exoplanetarchive.ipac.caltech.edu%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check for 'Exoplanet Research' bookmark folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%exoplanet research%' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS=1
            # Check for archive link inside that folder
            ARCHIVE_BOOKMARK_EXISTS=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 AND p.url LIKE '%exoplanetarchive%'
                 AND (b.parent=$FOLDER_ID OR b.parent IN (SELECT id FROM moz_bookmarks WHERE parent=$FOLDER_ID));" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Analyze Output File
JSON_FILE="/home/ga/Documents/jwst_targets.json"
FILE_EXISTS=0
FILE_FRESH=0
FILE_CONTENT=""

if [ -f "$JSON_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi
    # Read content safely (max 10KB to prevent issues)
    FILE_CONTENT=$(head -c 10240 "$JSON_FILE" | base64 -w 0)
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "archive_visits": $ARCHIVE_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "archive_bookmark_exists": $ARCHIVE_BOOKMARK_EXISTS,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_content_b64": "$FILE_CONTENT"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"