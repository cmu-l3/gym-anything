#!/bin/bash
# export_result.sh - Post-task hook for osha_construction_safety_research
set -e

echo "=== Exporting OSHA Task Results ==="

# 1. Capture Final Screenshot (Evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 3. Locate Firefox Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Try to find it again if setup failed to record it correctly
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Export Firefox Data (History & Bookmarks)
HISTORY_COUNT=0
BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_COUNT_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Close Firefox to flush WAL to DB
    pkill -u ga -f firefox 2>/dev/null || true
    sleep 2
    
    # Copy DB to temp location to read safely
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History: Distinct OSHA pages visited after task start
        HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h 
             JOIN moz_places p ON h.place_id = p.id 
             WHERE p.url LIKE '%osha.gov%' 
             AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        # Check Bookmark Folder "OSHA Construction Safety" (case-insensitive)
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks 
             WHERE type=2 AND title LIKE '%OSHA%Construction%Safety%' LIMIT 1;" 2>/dev/null || echo "")
             
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_FOUND="true"
            # Count bookmarks inside this folder
            BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks 
                 WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Check PDF Download
# Look for any PDF in Downloads created/modified after task start > 5KB
PDF_FOUND="false"
PDF_FILENAME=""
# Find files in Downloads, newer than task start, ending in pdf
FOUND_PDF=$(find /home/ga/Downloads -type f -name "*.pdf" -newermt "@$TASK_START" -size +5k -print -quit 2>/dev/null)

if [ -n "$FOUND_PDF" ]; then
    PDF_FOUND="true"
    PDF_FILENAME=$(basename "$FOUND_PDF")
fi

# 6. Check Output Text File
CHECKLIST_FILE="/home/ga/Documents/safety_compliance_checklist.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_FRESH="false"

if [ -f "$CHECKLIST_FILE" ]; then
    FILE_EXISTS="true"
    # Check freshness
    FILE_MTIME=$(stat -c %Y "$CHECKLIST_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
    # Read content (base64 encode to safely transport via JSON)
    FILE_CONTENT=$(cat "$CHECKLIST_FILE" | base64 -w 0)
fi

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "history_osha_visits": $HISTORY_COUNT,
    "bookmark_folder_found": $BOOKMARK_FOLDER_FOUND,
    "bookmarks_in_folder": $BOOKMARK_COUNT_IN_FOLDER,
    "pdf_downloaded": $PDF_FOUND,
    "pdf_filename": "$PDF_FILENAME",
    "checklist_file_exists": $FILE_EXISTS,
    "checklist_file_fresh": $FILE_FRESH,
    "checklist_content_b64": "$FILE_CONTENT"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"