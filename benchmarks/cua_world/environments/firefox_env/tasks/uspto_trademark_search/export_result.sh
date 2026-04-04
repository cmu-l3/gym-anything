#!/bin/bash
# export_result.sh - Post-task hook for uspto_trademark_search

set -e
echo "=== Exporting Task Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Close Firefox to flush SQLite WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load configuration
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Analyze Firefox Data (History & Bookmarks)
USPTO_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
USPTO_BOOKMARKS_COUNT=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    DB_PATH="$PROFILE_DIR/places.sqlite"
    # Copy DB to temp to avoid locks
    cp "$DB_PATH" /tmp/places_dump.sqlite

    # Query History: Visits to uspto.gov after task start
    USPTO_VISITS=$(sqlite3 /tmp/places_dump.sqlite \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h \
         JOIN moz_places p ON h.place_id = p.id \
         WHERE p.url LIKE '%uspto.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Query Bookmarks: Folder "Trademark Research"
    FOLDER_ID=$(sqlite3 /tmp/places_dump.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Trademark Research';" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Count bookmarks inside this folder that are uspto.gov links
        USPTO_BOOKMARKS_COUNT=$(sqlite3 /tmp/places_dump.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks b \
             JOIN moz_places p ON b.fk = p.id \
             WHERE b.parent=$FOLDER_ID AND p.url LIKE '%uspto.gov%';" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_dump.sqlite
fi

# 5. Analyze JSON Report File
REPORT_PATH="/home/ga/Documents/trademark_report.json"
REPORT_EXISTS="false"
REPORT_FRESH="false"
REPORT_CONTENT="{}"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
    
    # Read content safely (if valid JSON)
    if jq . "$REPORT_PATH" >/dev/null 2>&1; then
        REPORT_CONTENT=$(cat "$REPORT_PATH")
    else
        REPORT_CONTENT="{\"error\": \"Invalid JSON\"}"
    fi
fi

# 6. Build Result JSON
# We embed the report content so the python verifier can parse it
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "uspto_visits": $USPTO_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "uspto_bookmarks_count": $USPTO_BOOKMARKS_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_content": $REPORT_CONTENT
}
EOF

echo "Export complete. Result saved to /tmp/task_result.json"
chmod 666 /tmp/task_result.json