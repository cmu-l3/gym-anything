#!/bin/bash
# export_result.sh - Post-task hook for dblp_bibtex_research

echo "=== Exporting dblp_bibtex_research results ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush databases
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Task Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 4. Check Output File (.bib)
BIB_FILE="/home/ga/Documents/deep_learning.bib"
FILE_EXISTS=0
FILE_FRESH=0
FILE_CONTENT=""

if [ -f "$BIB_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$BIB_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi
    # Read content (base64 encode to safely transport via JSON)
    FILE_CONTENT=$(base64 -w 0 "$BIB_FILE")
fi

# 5. Check Firefox History & Bookmarks
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

DBLP_VISITS=0
BOOKMARK_FOLDER_EXISTS=0
DBLP_BOOKMARKS_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check visits to dblp.org
        DBLP_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%dblp.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
        
        # Check for 'Bibliography Sources' folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%bibliography sources%' LIMIT 1;" 2>/dev/null || echo "")
        
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS=1
            # Count bookmarks to dblp inside this folder
            DBLP_BOOKMARKS_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 
                 AND p.url LIKE '%dblp.org%'
                 AND b.parent=$FOLDER_ID;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_content_b64": "$FILE_CONTENT",
    "dblp_visits": $DBLP_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "dblp_bookmarks_count": $DBLP_BOOKMARKS_COUNT
}
EOF

# Move to final location (handle perms)
rm -f /tmp/dblp_result.json 2>/dev/null || sudo rm -f /tmp/dblp_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/dblp_result.json
chmod 666 /tmp/dblp_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/dblp_result.json"