#!/bin/bash
# export_result.sh - Post-task hook for school_lunch_menu_planning

echo "=== Exporting school_lunch_menu_planning results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL (Write-Ahead Logging) to disk
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# Fallback profile search if setup didn't save it
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Check Output File (JSON)
JSON_FILE="/home/ga/Documents/weekly_menu_plan.json"
JSON_EXISTS=0
JSON_FRESH=0
JSON_CONTENT="{}"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH=1
    fi
    # Read content safely (max 100KB to prevent issues)
    JSON_CONTENT=$(head -c 100000 "$JSON_FILE" | jq -c . 2>/dev/null || cat "$JSON_FILE")
fi

# 5. Check Firefox History & Bookmarks via SQLite
VISITS_FDC=0
VISITS_FNS=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARK_COUNT=0
USDA_BOOKMARK_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to read
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check Visits (FoodData Central & FNS)
        VISITS_FDC=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%fdc.nal.usda.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        VISITS_FNS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%fns.usda.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check Bookmark Folder "Menu Planning Resources"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Menu Planning Resources' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS=1
            
            # Count bookmarks in that folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=${FOLDER_ID};" 2>/dev/null || echo "0")
                
            # Count USDA bookmarks in that folder
            USDA_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.type=1 AND b.parent=${FOLDER_ID} AND p.url LIKE '%usda.gov%';" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Create Result JSON
OUTPUT_JSON="/tmp/task_result.json"
cat > "$OUTPUT_JSON" << EOF
{
  "task_start_timestamp": $TASK_START,
  "json_file_exists": $JSON_EXISTS,
  "json_file_fresh": $JSON_FRESH,
  "visits_fdc": $VISITS_FDC,
  "visits_fns": $VISITS_FNS,
  "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
  "bookmark_count": $BOOKMARK_COUNT,
  "usda_bookmark_count": $USDA_BOOKMARK_COUNT,
  "menu_json_content": $JSON_CONTENT
}
EOF

# Ensure permissions
chmod 666 "$OUTPUT_JSON" 2>/dev/null || true

echo "Export complete. Result saved to $OUTPUT_JSON"