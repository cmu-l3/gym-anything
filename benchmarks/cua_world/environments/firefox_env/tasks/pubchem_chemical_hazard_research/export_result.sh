#!/bin/bash
# export_result.sh - Post-task export for PubChem Chemical Hazard Research

echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Prepare Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert to microseconds for Firefox history timestamp comparison
TASK_START_US=$((TASK_START * 1000000))

# 3. Check Output File
OUTPUT_FILE="/home/ga/Documents/chemical_hazard_summary.json"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Extract Browser Data (History & Bookmarks)
# Kill Firefox to flush WAL to main DB
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Metrics
PUBCHEM_VISITS=0
BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_COUNT_IN_FOLDER=0
PUBCHEM_BOOKMARKS_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Create temp copy
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check History: Visits to PubChem compound pages
    PUBCHEM_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h \
         JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%pubchem.ncbi.nlm.nih.gov/compound/%' \
         AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check Bookmarks: Find folder 'Chemical Safety Research'
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Chemical Safety Research' LIMIT 1;" 2>/dev/null)
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_FOUND="true"
        
        # Count items in this folder
        BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
            
        # Count PubChem URLs in this folder
        PUBCHEM_BOOKMARKS_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks b \
             JOIN moz_places p ON b.fk=p.id \
             WHERE b.parent=$FOLDER_ID \
             AND b.type=1 \
             AND p.url LIKE '%pubchem.ncbi.nlm.nih.gov%';" 2>/dev/null || echo "0")
    fi
    
    rm -f "$TEMP_DB"
fi

# 5. Create Result JSON
# Note: We do not put the content of the user's JSON file here.
# The verifier will read the user's file directly using copy_from_env.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_file_size": $FILE_SIZE,
    "pubchem_history_visits": $PUBCHEM_VISITS,
    "bookmark_folder_found": $BOOKMARK_FOLDER_FOUND,
    "bookmarks_in_folder": $BOOKMARK_COUNT_IN_FOLDER,
    "pubchem_bookmarks_in_folder": $PUBCHEM_BOOKMARKS_IN_FOLDER,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="