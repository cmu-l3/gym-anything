#!/bin/bash
# export_result.sh - Post-task hook for nba_scouting_comparison

echo "=== Exporting NBA Scouting Result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 3. Locate Firefox Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Retry finding profile if temp file failed
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Initialize result variables
HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARK_COUNT=0
FILE_EXISTS=0
FILE_FRESH=0
FILE_CONTENT="{}"

# 5. Query Firefox Database (History & Bookmarks)
if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"

    # Check History: Visits to basketball-reference.com after task start
    HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h \
         JOIN moz_places p ON h.place_id = p.id \
         WHERE p.url LIKE '%basketball-reference.com%' \
         AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmarks: "NBA Scouting" folder
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE title='NBA Scouting' AND type=2;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS=1
        # Count bookmarks inside this folder
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi
    
    rm -f "$TEMP_DB"
fi

# 6. Check Output JSON File
OUTPUT_FILE="/home/ga/Documents/nba_comparison.json"
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi

    # Read content if valid JSON
    if jq . "$OUTPUT_FILE" >/dev/null 2>&1; then
        FILE_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# 7. Create Result JSON
# Use a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "history_count": $HISTORY_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_content": $FILE_CONTENT
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/nba_task_result.json
chmod 644 /tmp/nba_task_result.json

echo "Export complete. Result saved to /tmp/nba_task_result.json"