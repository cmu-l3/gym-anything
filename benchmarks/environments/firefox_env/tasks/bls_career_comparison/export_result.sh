#!/bin/bash
# export_result.sh - Post-task hook for bls_career_comparison

echo "=== Exporting bls_career_comparison results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Stop Firefox to flush SQLite WAL to disk
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Check Files (Existence & Freshness)
JSON_PATH="/home/ga/Documents/career_comparison.json"
SUMMARY_PATH="/home/ga/Documents/career_summary.txt"

JSON_EXISTS="false"
JSON_FRESH="false"
SUMMARY_EXISTS="false"
SUMMARY_FRESH="false"
SUMMARY_CONTENT=""

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH="true"
    fi
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SUMMARY_FRESH="true"
    fi
    # Read first 500 chars of summary for verification
    SUMMARY_CONTENT=$(head -c 500 "$SUMMARY_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# 5. Check Firefox History & Bookmarks
PLACES_DB="$PROFILE_DIR/places.sqlite"
BLS_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
BLS_BOOKMARK_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null

    if [ -f "$TEMP_DB" ]; then
        # History: Count distinct BLS OOH pages visited after start
        BLS_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h 
             JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%bls.gov/ooh%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # Bookmarks: Check for 'Career Research' folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Career Research' LIMIT 1;" 2>/dev/null || echo "")
        
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS="true"
            # Count bookmarks inside this folder that are BLS links
            # Recursive check not strictly needed if agent follows simple instructions, 
            # but checking direct children is safer.
            BLS_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b 
                 JOIN moz_places p ON b.fk=p.id
                 WHERE b.parent=$FOLDER_ID AND b.type=1 AND p.url LIKE '%bls.gov%';" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Parse JSON Content (Safe Python Extraction)
# We embed a small python script to validate the user's JSON structure inside the container
# This ensures we get structured data out even if the user's JSON is slightly malformed
PYTHON_RESULT=$(python3 -c "
import json, sys
try:
    with open('$JSON_PATH', 'r') as f:
        data = json.load(f)
    print(json.dumps(data))
except Exception:
    print('{}')
")

# 7. Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "json_exists": $JSON_EXISTS,
    "json_fresh": $JSON_FRESH,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_fresh": $SUMMARY_FRESH,
    "summary_content": "$SUMMARY_CONTENT",
    "bls_history_visits": $BLS_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bls_bookmark_count": $BLS_BOOKMARK_COUNT,
    "json_content": $PYTHON_RESULT
}
EOF

# 8. Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json