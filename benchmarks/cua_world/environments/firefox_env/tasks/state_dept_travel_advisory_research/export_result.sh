#!/bin/bash
# export_result.sh - Post-task hook for state_dept_travel_advisory_research

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Force Flush Firefox Database (Kill process)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROFILE_DIR=$(cat /tmp/firefox_profile_path.txt 2>/dev/null || echo "")
TASK_START_US=$((TASK_START * 1000000))

# 4. Analyze Firefox History & Bookmarks
VISITED_EGYPT="false"
VISITED_JAPAN="false"
VISITED_INDIA="false"
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
CORRECT_BOOKMARKS=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Create temp copy to read
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite
    
    # Check History (visits to specific country pages)
    # URLs typically end in Egypt.html, Japan.html, India.html
    VISITED_EGYPT=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) > 0 FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%travel.state.gov%' AND p.url LIKE '%Egypt.html%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "false")
         
    VISITED_JAPAN=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) > 0 FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%travel.state.gov%' AND p.url LIKE '%Japan.html%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "false")
         
    VISITED_INDIA=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) > 0 FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%travel.state.gov%' AND p.url LIKE '%India.html%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "false")

    # Check Bookmark Folder "Travel Risk Brief"
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Travel Risk Brief' LIMIT 1;" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Count bookmarks in that folder
        BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
            
        # Count bookmarks that look like state.gov pages
        CORRECT_BOOKMARKS=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id \
             WHERE b.parent=$FOLDER_ID AND b.type=1 AND p.url LIKE '%travel.state.gov%';" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 5. Check Output File
OUTPUT_FILE="/home/ga/Documents/travel_risk_brief.json"
FILE_EXISTS="false"
FILE_FRESH="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Check creation/mod time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 6. Create Export JSON
# We don't verify JSON content here; we let python do it.
# We just pass the file paths and sqlite analysis results.
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "visited_egypt": $([ "$VISITED_EGYPT" = "1" ] && echo "true" || echo "false"),
    "visited_japan": $([ "$VISITED_JAPAN" = "1" ] && echo "true" || echo "false"),
    "visited_india": $([ "$VISITED_INDIA" = "1" ] && echo "true" || echo "false"),
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count_in_folder": $BOOKMARK_COUNT,
    "correct_bookmarks_in_folder": $CORRECT_BOOKMARKS,
    "output_file_exists": $FILE_EXISTS,
    "output_file_fresh": $FILE_FRESH,
    "output_file_path": "$OUTPUT_FILE"
}
EOF

echo "Export complete. Result saved to /tmp/task_result.json"