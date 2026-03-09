#!/bin/bash
# export_result.sh - Post-task hook for census_telehealth_demographic_study

echo "=== Exporting Census Task Results ==="

# 1. Capture Final Screenshot (Evidence of final state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to ensure database WAL is flushed
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# 3. Gather Paths and Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"
OUTPUT_FILE="/home/ga/Documents/telehealth_pilot_data.json"

# 4. Check Output File Status
FILE_EXISTS="false"
FILE_FRESH="false"
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 5. Query Firefox Database (History & Bookmarks)
HISTORY_CENSUS_VISITS=0
HISTORY_COMPARISON_VISIT="false"
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_URL_CORRECT="false"

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check 1: Visits to quickfacts
    HISTORY_CENSUS_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%census.gov/quickfacts%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check 2: Specific comparison URL patterns (agent selected counties)
    # The URL usually looks like .../table/PST045222/12119,06041,04025 (FIPS codes) 
    # OR .../table/PST045223/sumtercountyflorida,marincountycalifornia,yavapaicountyarizona
    # We check for presence of county identifiers in URL
    COUNTY_CHECK=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%census.gov/quickfacts%' 
         AND (p.url LIKE '%sumter%' OR p.url LIKE '%12119%')
         AND (p.url LIKE '%marin%' OR p.url LIKE '%06041%')
         AND (p.url LIKE '%yavapai%' OR p.url LIKE '%04025%')
         AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
    
    if [ "$COUNTY_CHECK" -gt 0 ]; then
        HISTORY_COMPARISON_VISIT="true"
    fi

    # Check 3: Bookmark Folder "Pilot Site Research"
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Pilot Site Research' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Check 4: Bookmark inside that folder pointing to quickfacts
        BM_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
             WHERE b.parent=$FOLDER_ID AND p.url LIKE '%census.gov/quickfacts%';" 2>/dev/null || echo "0")
        
        if [ "$BM_COUNT" -gt 0 ]; then
            BOOKMARK_URL_CORRECT="true"
        fi
    fi

    rm -f "$TEMP_DB"
fi

# 6. Create Result JSON
cat > /tmp/task_result.json << EOF
{
  "file_exists": $FILE_EXISTS,
  "file_fresh": $FILE_FRESH,
  "history_visits": $HISTORY_CENSUS_VISITS,
  "history_comparison_found": $HISTORY_COMPARISON_VISIT,
  "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
  "bookmark_correct": $BOOKMARK_URL_CORRECT,
  "task_start_time": $TASK_START,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Safe Copy for Output File (if it exists)
if [ "$FILE_EXISTS" == "true" ]; then
    cp "$OUTPUT_FILE" /tmp/telehealth_pilot_data_submission.json
fi

echo "Result export complete."
cat /tmp/task_result.json