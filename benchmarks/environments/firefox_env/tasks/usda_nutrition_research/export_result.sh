#!/bin/bash
# export_result.sh - Post-task hook for usda_nutrition_research

echo "=== Exporting USDA Nutrition Research results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_START_US=$((TASK_START * 1000000))

# 3. Kill Firefox to ensure database is flushed (WAL checkpoint)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 4. Check Output File
OUTPUT_FILE="/home/ga/Documents/nutrition_reference.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
    # Read content (base64 encoded to handle newlines/special chars safely in JSON)
    FILE_CONTENT=$(base64 -w 0 "$OUTPUT_FILE")
fi

# 5. Analyze Firefox History & Bookmarks
PROFILE_DIR=$(cat /tmp/firefox_profile_path.txt 2>/dev/null || echo "")
HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite
    
    # Check History (visits to fdc.nal.usda.gov)
    HISTORY_COUNT=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h \
         JOIN moz_places p ON h.place_id = p.id \
         WHERE p.url LIKE '%fdc.nal.usda.gov%' \
         AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check Bookmark Folder "Nutrition Research"
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE title = 'Nutrition Research' AND type = 2;" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Count bookmarks inside that folder that point to USDA
        BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks b \
             JOIN moz_places p ON b.fk = p.id \
             WHERE b.parent = $FOLDER_ID \
             AND b.type = 1 \
             AND p.url LIKE '%fdc.nal.usda.gov%';" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/usda_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_content_b64": "$FILE_CONTENT",
    "history_visits": $HISTORY_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move to final location (handle permissions)
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"