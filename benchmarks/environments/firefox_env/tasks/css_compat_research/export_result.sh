#!/bin/bash
# export_result.sh - Post-task hook for css_compat_research

echo "=== Exporting CSS Compatibility Research Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to ensure WAL is flushed to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Get setup info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
# Convert to microseconds for Mozilla timestamp comparison
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"
echo "Analyzing database: $PLACES_DB"

# Initialize metrics
MDN_VISITS=0
CANIUSE_VISITS=0
W3C_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks/corruption during read
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check History (Visits AFTER task start)
    # MDN
    MDN_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%developer.mozilla.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Can I Use
    CANIUSE_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%caniuse.com%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # W3C / CSSWG
    W3C_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.url) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE (p.url LIKE '%w3.org%' OR p.url LIKE '%csswg.org%') AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmarks
    # Find folder id
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE title='CSS Compatibility Research' AND type=2 LIMIT 1;" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Count bookmarks in that folder
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi
    
    rm -f "$TEMP_DB"
else
    echo "ERROR: places.sqlite not found."
fi

# Check Report File
REPORT_PATH="/home/ga/Documents/css_compatibility_report.json"
REPORT_EXISTS="false"
REPORT_FRESH="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
fi

# Create result JSON for verifier
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "history": {
        "mdn_visits": $MDN_VISITS,
        "caniuse_visits": $CANIUSE_VISITS,
        "w3c_visits": $W3C_VISITS
    },
    "bookmarks": {
        "folder_exists": $BOOKMARK_FOLDER_EXISTS,
        "count": $BOOKMARK_COUNT
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "fresh": $REPORT_FRESH,
        "path": "$REPORT_PATH"
    }
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json