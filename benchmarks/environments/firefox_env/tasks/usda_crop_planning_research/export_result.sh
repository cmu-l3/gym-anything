#!/bin/bash
# export_result.sh - Post-task hook for usda_crop_planning_research

echo "=== Exporting USDA Crop Planning Research results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Kill Firefox to flush places.sqlite WAL file
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Locate profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search if temp file missing
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"

# Initialize metrics
USDA_VISITS=0
NASS_VISITS=0
ERS_VISITS=0
FOLDER_EXISTS="false"
FOLDER_ID=""
USDA_BOOKMARKS_COUNT=0
TOTAL_BOOKMARKS_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy DB for analysis
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    if [ -f "$TEMP_DB" ]; then
        # 1. Check History
        # Count distinct USDA pages visited after task start
        USDA_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%usda.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        NASS_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%nass.usda.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        ERS_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%ers.usda.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # 2. Check Bookmarks
        # Find folder named 'Crop Planning Research' (case-insensitive)
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%crop planning research%' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS="true"
            
            # Count bookmarks in that folder that are USDA links
            USDA_BOOKMARKS_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=$FOLDER_ID AND b.type=1 AND p.url LIKE '%usda.gov%';" 2>/dev/null || echo "0")
                 
            # Count total bookmarks in folder
            TOTAL_BOOKMARKS_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 3. Check Output File
OUTPUT_FILE="/home/ga/Documents/crop_planning_advisory.json"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read file content (safe read)
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "usda_visits": $USDA_VISITS,
    "nass_visits": $NASS_VISITS,
    "ers_visits": $ERS_VISITS,
    "bookmark_folder_exists": $FOLDER_EXISTS,
    "usda_bookmarks_count": $USDA_BOOKMARKS_COUNT,
    "total_bookmarks_in_folder": $TOTAL_BOOKMARKS_IN_FOLDER,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK
}
EOF

# Move to standard location with relaxed permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"