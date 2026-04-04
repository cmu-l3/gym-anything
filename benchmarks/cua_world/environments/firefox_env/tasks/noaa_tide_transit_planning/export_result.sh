#!/bin/bash
# export_result.sh - Post-task hook for noaa_tide_transit_planning

echo "=== Exporting NOAA Tide Transit Planning results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Read setup info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# --- CHECK BOOKMARKS & HISTORY ---
PLACES_DB="$PROFILE_DIR/places.sqlite"
NOAA_VISITS=0
FOLDER_EXISTS=0
BOOKMARK_COUNT=0
HAS_BATTERY_BM=0
HAS_KINGS_BM=0

if [ -f "$PLACES_DB" ]; then
    # Snapshot DB
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # History check
        NOAA_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%tidesandcurrents.noaa.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Folder check "Project Alpha Logistics"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%project alpha logistics%' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS=1
            
            # Count bookmarks in folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
                
            # Check for specific station IDs in bookmarks (Battery: 8518750, Kings: 8516945)
            HAS_BATTERY_BM=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=${FOLDER_ID} AND p.url LIKE '%8518750%';" 2>/dev/null || echo "0")
                 
            HAS_KINGS_BM=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=${FOLDER_ID} AND p.url LIKE '%8516945%';" 2>/dev/null || echo "0")
        fi
        rm -f "$TEMP_DB"
    fi
fi

# --- CHECK OUTPUT FILE ---
OUTPUT_FILE="/home/ga/Documents/barge_schedule.json"
FILE_EXISTS=0
FILE_FRESH=0
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi
    # Read file content safely
    FILE_CONTENT=$(cat "$OUTPUT_FILE" 2>/dev/null)
fi

# Create result JSON
RESULT_JSON="/tmp/task_result.json"
cat > "$RESULT_JSON" << EOF
{
  "task_start": $TASK_START,
  "noaa_visits": $NOAA_VISITS,
  "folder_exists": $FOLDER_EXISTS,
  "bookmark_count": $BOOKMARK_COUNT,
  "has_battery_bm": $HAS_BATTERY_BM,
  "has_kings_bm": $HAS_KINGS_BM,
  "file_exists": $FILE_EXISTS,
  "file_fresh": $FILE_FRESH
}
EOF

# Append file content if it exists (using Python to escape JSON properly)
python3 -c "
import json
try:
    with open('$RESULT_JSON', 'r') as f:
        res = json.load(f)
    content = '''$FILE_CONTENT'''
    try:
        res['file_content'] = json.loads(content)
        res['file_valid_json'] = True
    except:
        res['file_content'] = content
        res['file_valid_json'] = False
    
    with open('$RESULT_JSON', 'w') as f:
        json.dump(res, f)
except Exception as e:
    print(e)
"

chmod 666 "$RESULT_JSON"
echo "Export complete."