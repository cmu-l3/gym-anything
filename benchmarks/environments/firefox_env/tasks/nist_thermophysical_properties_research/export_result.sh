#!/bin/bash
# export_result.sh - Post-task export for NIST Research Task

echo "=== Exporting NIST Research Results ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush WAL to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# 3. Gather Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000)) # Firefox stores time in microseconds

# 4. Check Output JSON File
OUTPUT_FILE="/home/ga/Documents/fluid_properties.json"
OUTPUT_EXISTS="false"
OUTPUT_FRESH="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_FRESH="true"
    fi
fi

# 5. Analyze Browser History & Bookmarks
PROFILE_DIR=$(cat /tmp/firefox_profile_path.txt 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Defaults
NIST_VISITS=0
FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
BOOKMARK_URLS=""

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to read
    TEMP_DB="/tmp/places_export.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check Visits to webbook.nist.gov
    NIST_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id = p.id \
         WHERE p.url LIKE '%webbook.nist.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check Bookmark Folder "Process Design Data"
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Process Design Data';" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        FOLDER_EXISTS="true"
        # Count bookmarks in this folder (type=1) that point to NIST
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id \
             WHERE b.parent = $FOLDER_ID AND b.type = 1 AND p.url LIKE '%nist.gov%';" 2>/dev/null || echo "0")
             
        # Get URLs for debug/verification
        BOOKMARK_URLS=$(sqlite3 "$TEMP_DB" \
            "SELECT p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id \
             WHERE b.parent = $FOLDER_ID AND b.type = 1;" 2>/dev/null | tr '\n' ',' || echo "")
    fi
    
    rm -f "$TEMP_DB"
fi

# 6. Create Result JSON
# We write this to a temp file then move it to /tmp/task_result.json safely
# We allow the verifier to read the output file directly via copy_from_env, 
# but we put metadata here.

cat > /tmp/temp_result.json <<EOF
{
  "task_start": $TASK_START,
  "output_exists": $OUTPUT_EXISTS,
  "output_fresh": $OUTPUT_FRESH,
  "nist_visits": $NIST_VISITS,
  "bookmark_folder_exists": $FOLDER_EXISTS,
  "bookmark_count": $BOOKMARK_COUNT,
  "bookmark_urls": "$BOOKMARK_URLS",
  "screenshot_path": "/tmp/task_final.png"
}
EOF

mv /tmp/temp_result.json /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json