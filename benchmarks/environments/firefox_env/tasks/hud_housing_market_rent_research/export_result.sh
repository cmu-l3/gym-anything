#!/bin/bash
# export_result.sh - Post-task hook for hud_housing_market_rent_research

echo "=== Exporting HUD FMR Research Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load setup variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Initialize result variables
HUD_HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_FOLDER_COUNT=0
HUD_BOOKMARKS_COUNT=0
FILE_EXISTS="false"
FILE_MTIME=0
FILE_CONTENT="{}"

# 5. Analyze Firefox Database
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Create temp copy
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite 2>/dev/null
    
    if [ -f /tmp/places_export.sqlite ]; then
        # Check History for huduser.gov
        HUD_HISTORY_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
             WHERE p.url LIKE '%huduser.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check for 'HUD FMR Audit' bookmark folder
        FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='HUD FMR Audit' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS="true"
            # Count items in that folder
            BOOKMARK_FOLDER_COUNT=$(sqlite3 /tmp/places_export.sqlite \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
            # Count how many look like HUD links
            HUD_BOOKMARKS_COUNT=$(sqlite3 /tmp/places_export.sqlite \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id \
                 WHERE b.parent=${FOLDER_ID} AND b.type=1 AND p.url LIKE '%huduser.gov%';" 2>/dev/null || echo "0")
        fi
        
        rm -f /tmp/places_export.sqlite
    fi
fi

# 6. Check JSON Output File
OUTPUT_PATH="/home/ga/Documents/fmr_audit_2024.json"
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Read content safely
    FILE_CONTENT=$(cat "$OUTPUT_PATH")
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/hud_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "hud_history_count": $HUD_HISTORY_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_folder_count": $BOOKMARK_FOLDER_COUNT,
    "hud_bookmarks_count": $HUD_BOOKMARKS_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "file_content_raw": $(echo "$FILE_CONTENT" | jq -R . 2>/dev/null || echo "\"\"")
}
EOF

# 8. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"