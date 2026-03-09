#!/bin/bash
# export_result.sh - Post-task hook for astronomy_observation_planning

echo "=== Exporting Astronomy Task Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to ensure database is flushed
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Gather Timing Info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 4. Locate Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ]; then
     PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

# 5. Inspect Firefox DB (History & Bookmarks)
ASTRO_HISTORY_COUNT=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite 2>/dev/null
    
    # Check History for relevant domains
    ASTRO_HISTORY_COUNT=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE (p.url LIKE '%timeanddate%' OR p.url LIKE '%heavens-above%' OR p.url LIKE '%in-the-sky%' OR p.url LIKE '%earthsky%' OR p.url LIKE '%imo.net%')
         AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check for 'Astronomy Tools' bookmark folder
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE '%Astronomy Tools%' LIMIT 1;" 2>/dev/null)
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Count bookmarks inside that folder
        BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=$FOLDER_ID;" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 6. Check Output File
OUTPUT_FILE="/home/ga/Documents/stargazing_plan.json"
FILE_EXISTS="false"
FILE_FRESH="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 7. Create Export JSON
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "astro_history_count": $ASTRO_HISTORY_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "output_file_exists": $FILE_EXISTS,
    "output_file_fresh": $FILE_FRESH
}
EOF

# Move to standard location with lenient permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Also copy the user's output file to tmp for the verifier to read easily
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$OUTPUT_FILE" /tmp/stargazing_plan_submit.json
    chmod 666 /tmp/stargazing_plan_submit.json
fi

echo "Export complete."