#!/bin/bash
# export_result.sh - Post-task hook for airport_facility_data_collection

echo "=== Exporting Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to force WAL flush to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load configuration
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# Fallback profile search if setup failed to record it correctly
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    for candidate in \
        "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
        "/home/ga/.mozilla/firefox/default.profile"; do
        if [ -f "$candidate/places.sqlite" ]; then
            PROFILE_DIR="$candidate"
            break
        fi
    done
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Initialize result variables
HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
PDF_EXISTS="false"
PDF_FILENAME=""
JSON_EXISTS="false"
JSON_CONTENT="{}"

# 5. Extract Data from Firefox Database
if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy to temp to safely query
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History for AirNav visits
        HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%airnav.com%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check for 'Mountain Airports' folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE '%Mountain Airports%' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS="true"
            # Count bookmarks inside this folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Check for PDF Download
# Look for any PDF in Downloads created/modified after task start
FOUND_PDF=$(find /home/ga/Downloads -maxdepth 1 -type f \( -name "*.pdf" -o -name "*.PDF" \) -newermt "@$TASK_START" 2>/dev/null | head -1)
if [ -n "$FOUND_PDF" ]; then
    PDF_EXISTS="true"
    PDF_FILENAME=$(basename "$FOUND_PDF")
fi

# 7. Check for JSON Output
JSON_PATH="/home/ga/Documents/airport_briefing.json"
if [ -f "$JSON_PATH" ]; then
    # Verify it was created during task
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_EXISTS="true"
        # Read content carefully
        JSON_CONTENT=$(cat "$JSON_PATH" 2>/dev/null || echo "{}")
    fi
fi

# 8. Create Result JSON
TEMP_RESULT=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_RESULT" << EOF
{
    "task_start_time": $TASK_START,
    "airnav_history_count": $HISTORY_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "pdf_downloaded": $PDF_EXISTS,
    "pdf_filename": "$PDF_FILENAME",
    "json_exists": $JSON_EXISTS,
    "json_path": "$JSON_PATH"
}
EOF

# Move to final location
chmod 666 "$TEMP_RESULT"
mv "$TEMP_RESULT" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"