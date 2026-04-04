#!/bin/bash
# export_result.sh - Post-task hook for ev_fleet_procurement_research

echo "=== Exporting EV Fleet Procurement Research results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Kill Firefox to flush WAL to main DB
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Locate profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"
OUTPUT_FILE="/home/ga/Documents/ev_fleet_analysis.json"

# Initialize verification vars
HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
REPORT_EXISTS="false"
REPORT_FRESH="false"
REPORT_CONTENT="{}"

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to read
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check History for fueleconomy.gov
    HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%fueleconomy.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmarks
    # 1. Check if folder 'EV Fleet Candidates' exists
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE title LIKE 'EV Fleet Candidates' AND type=2 LIMIT 1;" 2>/dev/null)
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # 2. Count bookmarks inside this folder that are from fueleconomy.gov
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
             WHERE b.parent=$FOLDER_ID AND p.url LIKE '%fueleconomy.gov%';" 2>/dev/null || echo "0")
    fi
    
    rm -f "$TEMP_DB"
fi

# Check Report File
if [ -f "$OUTPUT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
    # Read content
    REPORT_CONTENT=$(cat "$OUTPUT_FILE")
fi

# Create Result JSON
TEMP_RESULT=$(mktemp)
cat <<EOF > "$TEMP_RESULT"
{
    "task_start": $TASK_START,
    "history_visits": $HISTORY_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_content": $REPORT_CONTENT
}
EOF

# Move to standard location
chmod 644 "$TEMP_RESULT"
mv "$TEMP_RESULT" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"