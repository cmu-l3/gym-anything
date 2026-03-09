#!/bin/bash
# export_result.sh - Post-task hook for dailymed_medication_research
set -e

echo "=== Exporting DailyMed Research Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 3. Kill Firefox to flush SQLite WAL (Write-Ahead Log)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 4. Analyze Firefox Database (History & Bookmarks)
DAILYMED_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
BOOKMARK_URLS=""

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB"

    # Check History (Visits to dailymed.nlm.nih.gov)
    DAILYMED_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h \
         JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%dailymed.nlm.nih.gov%' \
         AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmark Folder
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Medication Reference';" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Count bookmarks in this folder
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        
        # Get URLs of bookmarks in this folder (for verification they are DailyMed links)
        BOOKMARK_URLS=$(sqlite3 "$TEMP_DB" \
            "SELECT p.url FROM moz_bookmarks b \
             JOIN moz_places p ON b.fk=p.id \
             WHERE b.parent=$FOLDER_ID AND b.type=1;" 2>/dev/null | tr '\n' ',' || echo "")
    fi
    
    rm -f "$TEMP_DB"
fi

# 5. Analyze PDF Downloads
# Count PDFs in Downloads folder created AFTER task start and > 50KB
PDF_COUNT=0
DOWNLOADED_FILES=""

# Find files: in Downloads, ending in .pdf (case insensitive), newer than task start
while IFS= read -r file; do
    if [ -f "$file" ]; then
        SIZE=$(stat -c %s "$file")
        # Check size > 50KB (51200 bytes) - DailyMed labels are usually large
        if [ "$SIZE" -gt 51200 ]; then
            PDF_COUNT=$((PDF_COUNT + 1))
            DOWNLOADED_FILES="$DOWNLOADED_FILES,$(basename "$file")"
        fi
    fi
done < <(find /home/ga/Downloads -type f -iname "*.pdf" -newer /tmp/task_start_time.txt 2>/dev/null)

# 6. Analyze JSON Output File Metadata (Content analyzed by verifier.py)
JSON_PATH="/home/ga/Documents/medication_reference.json"
JSON_EXISTS="false"
JSON_FRESH="false"
JSON_SIZE=0

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH")
    JSON_SIZE=$(stat -c %s "$JSON_PATH")
    
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH="true"
    fi
fi

# 7. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "dailymed_visits": $DAILYMED_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "bookmark_urls": "$BOOKMARK_URLS",
    "pdf_download_count": $PDF_COUNT,
    "downloaded_files": "$DOWNLOADED_FILES",
    "json_exists": $JSON_EXISTS,
    "json_fresh": $JSON_FRESH,
    "json_size": $JSON_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="