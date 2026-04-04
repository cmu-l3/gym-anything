#!/bin/bash
# export_result.sh - Post-task hook for wayback_web_history_research
set -e

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 3. Kill Firefox to flush SQLite WAL (Write-Ahead Log)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 4. Analyze Firefox Database (History & Bookmarks)
PLACES_DB="$PROFILE_DIR/places.sqlite"
WAYBACK_VISITS=0
BOOKMARK_FOLDER_EXISTS=0
WAYBACK_BOOKMARKS=0

if [ -f "$PLACES_DB" ]; then
    # Force checkpoint just in case
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy DB to temp file for analysis
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History: Visits to web.archive.org since task start
        WAYBACK_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h 
             JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%web.archive.org/web/%' 
             AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check Bookmarks: Folder "Web Archive Research"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Web Archive Research' LIMIT 1;" \
            2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS=1
            # Count bookmarks inside this folder that are Wayback URLs
            WAYBACK_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b 
                 JOIN moz_places p ON b.fk=p.id
                 WHERE b.parent=${FOLDER_ID} 
                 AND b.type=1 
                 AND p.url LIKE '%web.archive.org%';" \
                2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
else
    echo "WARNING: Firefox places.sqlite not found."
fi

# 5. Check Output JSON File
REPORT_PATH="/home/ga/Documents/web_history_report.json"
REPORT_EXISTS=0
REPORT_FRESH=0
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH=1
    fi
fi

# 6. Create Result JSON
# We export browser state stats here. The actual report content is read by verifier.py
TEMP_JSON=$(mktemp /tmp/export_data.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "wayback_history_visits": $WAYBACK_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "wayback_bookmarks_count": $WAYBACK_BOOKMARKS,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_fresh": $REPORT_FRESH,
    "report_file_size": $REPORT_SIZE,
    "report_file_path": "$REPORT_PATH"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json