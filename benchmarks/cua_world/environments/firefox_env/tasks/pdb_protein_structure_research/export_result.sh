#!/bin/bash
# export_result.sh - Post-task hook for pdb_protein_structure_research

echo "=== Exporting PDB Research Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush databases
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Context
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Check JSON Report
REPORT_FILE="/home/ga/Documents/protein_structures.json"
REPORT_EXISTS="false"
REPORT_CONTENT="{}"
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# 5. Check Downloaded File (Looking for *4hhb* or *4HHB* in Downloads)
DOWNLOAD_FOUND="false"
DOWNLOAD_FILENAME=""
DOWNLOAD_SIZE=0
# Find newest file matching pattern created after task start
TARGET_DOWNLOAD=$(find /home/ga/Downloads -type f \( -name "*4hhb*" -o -name "*4HHB*" \) -newermt "@$TASK_START" -printf "%T@ %p\n" | sort -n | tail -1 | awk '{print $2}')

if [ -n "$TARGET_DOWNLOAD" ]; then
    DOWNLOAD_FOUND="true"
    DOWNLOAD_FILENAME=$(basename "$TARGET_DOWNLOAD")
    DOWNLOAD_SIZE=$(stat -c %s "$TARGET_DOWNLOAD")
    # Read first few lines to verify it looks like PDB format
    DOWNLOAD_HEADER=$(head -n 5 "$TARGET_DOWNLOAD")
fi

# 6. Analyze History and Bookmarks
HISTORY_VISITS=0
BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_COUNT=0
URLS_BOOKMARKED=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Use a temp copy
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite
    
    # Check history for rcsb.org
    HISTORY_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%rcsb.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check for Bookmark Folder "Protein Research"
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE '%Protein Research%';" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_FOUND="true"
        # Count bookmarks inside this folder
        BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
            
        # Check if they link to rcsb.org
        URLS_BOOKMARKED=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id \
             WHERE b.parent=$FOLDER_ID AND b.type=1 AND p.url LIKE '%rcsb.org%';" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "download_found": $DOWNLOAD_FOUND,
    "download_filename": "$DOWNLOAD_FILENAME",
    "download_size": $DOWNLOAD_SIZE,
    "history_rcsb_visits": $HISTORY_VISITS,
    "bookmark_folder_found": $BOOKMARK_FOLDER_FOUND,
    "bookmark_count": $BOOKMARK_COUNT,
    "rcsb_bookmarks_count": $URLS_BOOKMARKED
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# If report exists, we copy it to a temp location for the verifier to read separately if needed,
# but since it's small, we can probably just rely on the verifier reading it from the container 
# using copy_from_env on the original path.

echo "Export complete. Result saved to /tmp/task_result.json"