#!/bin/bash
# export_result.sh - Post-task hook for epa_tri_community_assessment

echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL (Write-Ahead Log)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Environment Variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
# Convert to microseconds for Firefox history timestamp comparison
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Analyze Firefox Data (History & Bookmarks)
EPA_VISITS=0
FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
EPA_BOOKMARKS=0

if [ -f "$PLACES_DB" ]; then
    # Force checkpoint to ensure data is in main DB file
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy to temp DB for analysis
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History: Visits to epa.gov after task start
        EPA_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%epa.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check Bookmarks: Folder "Community Health Research"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title)='community health research' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS="true"
            # Count bookmarks in that folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
                
            # Count bookmarks in that folder that are specifically EPA URLs
            EPA_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=${FOLDER_ID} AND b.type=1 AND p.url LIKE '%epa.gov%';" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Analyze Downloads
# Find files in Downloads folder created/modified after task start, larger than 10KB
DOWNLOAD_FOUND="false"
DOWNLOAD_FILENAME=""
DOWNLOAD_SIZE=0

# Loop through files in Downloads
while IFS= read -r file; do
    if [ -f "$file" ]; then
        FSIZE=$(stat -c %s "$file" 2>/dev/null || echo "0")
        # Check if > 10KB (approx 10240 bytes)
        if [ "$FSIZE" -gt 10240 ]; then
            DOWNLOAD_FOUND="true"
            DOWNLOAD_FILENAME=$(basename "$file")
            DOWNLOAD_SIZE=$FSIZE
            break # Found one valid file, that's enough for the check
        fi
    fi
done < <(find /home/ga/Downloads -type f -newermt "@$TASK_START" 2>/dev/null)

# 6. Analyze Report File
REPORT_PATH="/home/ga/Documents/tri_community_report.txt"
REPORT_EXISTS="false"
REPORT_FRESH="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    R_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$R_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
    
    # Read content (limit size to prevent huge JSON)
    REPORT_CONTENT=$(head -c 10000 "$REPORT_PATH" | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# 7. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start_ts": $TASK_START,
    "epa_visits": $EPA_VISITS,
    "bookmark_folder_exists": $FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "epa_bookmarks_count": $EPA_BOOKMARKS,
    "download_found": $DOWNLOAD_FOUND,
    "download_filename": "$DOWNLOAD_FILENAME",
    "download_size": $DOWNLOAD_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_content": "$REPORT_CONTENT"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json