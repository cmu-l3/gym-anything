#!/bin/bash
# export_result.sh - Post-task hook for FEC Super PAC Analysis
set -e

echo "=== Exporting FEC Super PAC Analysis results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush WAL (Write-Ahead Log) to main database
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Get task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Locate Firefox profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 1. Analyze Browser History & Bookmarks
FEC_VISITS=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARKS_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check history for fec.gov visits
        FEC_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%fec.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check for 'FEC Research' bookmark folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='FEC Research' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS=1
            # Count bookmarks within this folder
            BOOKMARKS_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 2. Check JSON Output File
OUTPUT_FILE="/home/ga/Documents/super_pac_financials.json"
FILE_EXISTS=0
FILE_FRESH=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi
fi

# 3. Create Export JSON
# We embed the content of the user's JSON file (if valid) into our result JSON for the verifier to parse safely
USER_JSON_CONTENT="{}"
if [ "$FILE_EXISTS" -eq 1 ]; then
    # Validate it's proper JSON before embedding, otherwise use empty object
    if jq . "$OUTPUT_FILE" >/dev/null 2>&1; then
        USER_JSON_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# Create result JSON
RESULT_JSON="/tmp/fec_task_result.json"
cat > "$RESULT_JSON" <<EOF
{
  "task_start_time": $TASK_START,
  "fec_visits": $FEC_VISITS,
  "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
  "bookmarks_in_folder": $BOOKMARKS_IN_FOLDER,
  "file_exists": $FILE_EXISTS,
  "file_fresh": $FILE_FRESH,
  "user_json_content": $USER_JSON_CONTENT
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"