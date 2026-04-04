#!/bin/bash
# export_result.sh - Post-task hook for world_bank_dev_research

echo "=== Exporting World Bank Research Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to force flush WAL to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load configuration
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
# Convert to microseconds for Firefox history timestamp comparison
TASK_START_US=$((TASK_START * 1000000))

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ]; then
    # Fallback search again if tmp file missing
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Analyze Browser Data (History & Bookmarks)
WB_VISITS=0
COUNTRY_VISITS=0
FOLDER_EXISTS=0
FOLDER_BOOKMARK_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy to temp DB
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    if [ -f "$TEMP_DB" ]; then
        # Check History: Visits to worldbank.org after task start
        WB_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%worldbank.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        # Check History: Visits related to target countries
        # Searching for URLs containing country names or ISO codes
        COUNTRY_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%worldbank.org%' 
             AND (p.url LIKE '%nigeria%' OR p.url LIKE '%NGA%' OR p.url LIKE '%kenya%' OR p.url LIKE '%KEN%' OR p.url LIKE '%south-africa%' OR p.url LIKE '%ZAF%')
             AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

        # Check Bookmarks: "World Bank Research" folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='World Bank Research' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS=1
            # Count bookmarks within this folder that match worldbank.org
            FOLDER_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=$FOLDER_ID AND b.type=1 AND p.url LIKE '%worldbank.org%';" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Check Report File
REPORT_PATH="/home/ga/Documents/world_bank_africa_report.json"
REPORT_EXISTS=0
REPORT_FRESH=0
REPORT_CONTENT="{}"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH=1
    fi
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_PATH" 2>/dev/null || echo "{}")
fi

# 6. Create Result JSON
TEMP_RESULT=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_RESULT" << EOF
{
    "task_start_time": $TASK_START,
    "wb_visits": $WB_VISITS,
    "country_visits": $COUNTRY_VISITS,
    "folder_exists": $FOLDER_EXISTS,
    "folder_bookmark_count": $FOLDER_BOOKMARK_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_content": $REPORT_CONTENT
}
EOF

# Move to standard location
rm -f /tmp/world_bank_result.json 2>/dev/null
mv "$TEMP_RESULT" /tmp/world_bank_result.json
chmod 644 /tmp/world_bank_result.json

echo "Export complete. Result saved to /tmp/world_bank_result.json"