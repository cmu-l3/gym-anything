#!/bin/bash
# export_result.sh - Post-task hook for press_freedom_analysis
# Exports browser state (history/bookmarks) and file metadata to JSON

echo "=== Exporting press_freedom_analysis results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to force SQLite WAL flush
echo "Closing Firefox..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load setup variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
# Convert to microseconds for Mozilla timestamp comparison
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Check Browser State (History & Bookmarks)
RSF_VISITS=0
FH_VISITS=0
CPJ_VISITS=0
FOLDER_EXISTS=0
FOLDER_BOOKMARK_COUNT=0
BOOKMARK_DOMAINS=""

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB"
    
    # Force WAL checkpoint if possible
    sqlite3 "$TEMP_DB" "PRAGMA wal_checkpoint;" 2>/dev/null || true

    if [ -f "$TEMP_DB" ]; then
        # History Checks
        RSF_VISITS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%rsf.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
        FH_VISITS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%freedomhouse.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
        CPJ_VISITS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%cpj.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

        # Bookmark Checks
        # Find folder id for "Press Freedom Research" (case-insensitive)
        FOLDER_ID=$(sqlite3 "$TEMP_DB" "SELECT id FROM moz_bookmarks WHERE type=2 AND LOWER(title) LIKE '%press freedom research%' LIMIT 1;" 2>/dev/null || echo "")
        
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS=1
            # Count bookmarks in that folder
            FOLDER_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=$FOLDER_ID;" 2>/dev/null || echo "0")
            
            # Get domains of bookmarks in that folder (for diversity check)
            BOOKMARK_URLS=$(sqlite3 "$TEMP_DB" "SELECT p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.type=1 AND b.parent=$FOLDER_ID;" 2>/dev/null)
            # Simple grep check for domains in the URLs
            BOOKMARK_DOMAINS=""
            if echo "$BOOKMARK_URLS" | grep -q "rsf.org"; then BOOKMARK_DOMAINS="${BOOKMARK_DOMAINS}rsf "; fi
            if echo "$BOOKMARK_URLS" | grep -q "freedomhouse.org"; then BOOKMARK_DOMAINS="${BOOKMARK_DOMAINS}fh "; fi
            if echo "$BOOKMARK_URLS" | grep -q "cpj.org"; then BOOKMARK_DOMAINS="${BOOKMARK_DOMAINS}cpj "; fi
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 5. Check Output File Metadata
OUTPUT_FILE="/home/ga/Documents/press_freedom_comparison.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 6. Create Result JSON
# Note: We do NOT parse the user's JSON here to avoid bash complexity/fragility.
# We pass the metadata to verifier.py, which will read the user's file directly.
RESULT_JSON="/tmp/task_result.json"

cat > "$RESULT_JSON" << EOF
{
  "task_start_time": $TASK_START,
  "history_visits": {
    "rsf": $RSF_VISITS,
    "freedom_house": $FH_VISITS,
    "cpj": $CPJ_VISITS
  },
  "bookmarks": {
    "folder_exists": $FOLDER_EXISTS,
    "count": $FOLDER_BOOKMARK_COUNT,
    "domains_present": "$BOOKMARK_DOMAINS"
  },
  "output_file": {
    "exists": $FILE_EXISTS,
    "fresh": $FILE_FRESH,
    "size": $FILE_SIZE,
    "path": "$OUTPUT_FILE"
  }
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"