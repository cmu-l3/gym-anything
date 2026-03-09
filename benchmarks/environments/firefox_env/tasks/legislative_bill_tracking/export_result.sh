#!/bin/bash
# export_result.sh - Post-task hook for legislative_bill_tracking

echo "=== Exporting legislative_bill_tracking results ==="

# 1. Capture final visual state
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Force Firefox to flush WAL to disk by killing it gracefully, then forcefully
pkill -u ga -f firefox 2>/dev/null || true
sleep 3
pkill -9 -u ga -f firefox 2>/dev/null || true

# 3. Load Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 4. Locate Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Retry search if not found in setup
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 5. Analyze Browser Data (History & Bookmarks)
HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARK_COUNT_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check History for Congress.gov visits
    HISTORY_COUNT=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h 
         JOIN moz_places p ON h.place_id = p.id 
         WHERE p.url LIKE '%congress.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check for Bookmark Folder "AI Legislation 118th"
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE '%AI Legislation 118th%';" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS=1
        # Count bookmarks inside this folder
        BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi
    
    rm -f "$TEMP_DB"
fi

# 6. Analyze PDF Download
PDF_PATH="/home/ga/Documents/Bills/hr5077_text.pdf"
PDF_EXISTS=0
PDF_SIZE=0
PDF_FRESH=0

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS=1
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_FRESH=1
    fi
fi

# 7. Analyze JSON Report File
REPORT_PATH="/home/ga/Documents/legislative_report.json"
REPORT_EXISTS=0
REPORT_FRESH=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH=1
    fi
fi

# 8. Create Result JSON
# We don't parse the user's JSON here to avoid bash JSON parsing hell.
# We just export the system state. The verifier will parse the user's JSON file directly.

cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "history_congress_visits": $HISTORY_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT_IN_FOLDER,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "pdf_fresh": $PDF_FRESH,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_path": "$REPORT_PATH"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json