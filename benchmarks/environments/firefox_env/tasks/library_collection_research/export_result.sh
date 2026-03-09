#!/bin/bash
# export_result.sh - Post-task hook for library_collection_research

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Force close Firefox to flush WAL (Write-Ahead Log) to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Get configuration
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert to microseconds for Firefox timestamp comparison
TASK_START_US=$((TASK_START * 1000000))

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ]; then
    # Fallback if setup didn't save it
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

echo "Analyzing Firefox profile at: $PROFILE_DIR"

# 4. Initialize metrics
HISTORY_LOC=0
HISTORY_GUTENBERG=0
HISTORY_OPENLIB=0
FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
BOOKMARK_DOMAINS_COUNT=0

# 5. Query Firefox Database (copy first to avoid locks)
if [ -f "$PLACES_DB" ]; then
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    # Checkpoint to ensure WAL is merged
    sqlite3 "$TEMP_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true

    if [ -f "$TEMP_DB" ]; then
        # History Checks (visits AFTER task start)
        HISTORY_LOC=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%loc.gov%') AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        HISTORY_GUTENBERG=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%gutenberg.org%') AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        HISTORY_OPENLIB=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%openlibrary.org%') AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

        # Bookmark Checks
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Collection Development' LIMIT 1;" 2>/dev/null || echo "")
        
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS="true"
            
            # Count bookmarks in that folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
            
            # Count distinct relevant domains in that folder
            # We look for the 3 target domains in the bookmarked URLs
            BOOKMARK_DOMAINS_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(DISTINCT CASE 
                    WHEN p.url LIKE '%loc.gov%' THEN 'loc'
                    WHEN p.url LIKE '%gutenberg.org%' THEN 'gut'
                    WHEN p.url LIKE '%openlibrary.org%' THEN 'open'
                    ELSE NULL END)
                 FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.parent=$FOLDER_ID AND b.type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
else
    echo "WARNING: places.sqlite not found."
fi

# 6. Check Report File
REPORT_PATH="/home/ga/Documents/bibliographic_report.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
    
    # Copy report to temp for verifier to access via copy_from_env
    cp "$REPORT_PATH" /tmp/bibliographic_report_export.json
    chmod 644 /tmp/bibliographic_report_export.json
fi

# 7. Create Verification JSON
OUTPUT_JSON="/tmp/task_result.json"
cat > "$OUTPUT_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "history_loc_count": $HISTORY_LOC,
    "history_gutenberg_count": $HISTORY_GUTENBERG,
    "history_openlib_count": $HISTORY_OPENLIB,
    "bookmark_folder_exists": $FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "bookmark_domain_spread": $BOOKMARK_DOMAINS_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_size": $FILE_SIZE
}
EOF

# Ensure permissions
chmod 644 "$OUTPUT_JSON"

echo "Export complete. Result saved to $OUTPUT_JSON"
cat "$OUTPUT_JSON"