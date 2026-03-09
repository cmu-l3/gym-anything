#!/bin/bash
# export_result.sh - Post-task hook for energystar_appliance_procurement

echo "=== Exporting Task Results ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Check for JSON output file
JSON_PATH="/home/ga/Documents/fridge_selection.json"
JSON_EXISTS="false"
JSON_VALID="false"
JSON_CONTENT="{}"

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    # Basic validation that it is JSON
    if jq . "$JSON_PATH" >/dev/null 2>&1; then
        JSON_VALID="true"
        JSON_CONTENT=$(cat "$JSON_PATH")
    fi
fi

# 3. Check for Downloaded Export File (.xlsx or .csv)
# We look for files created AFTER task start
DOWNLOAD_FOUND="false"
DOWNLOAD_FILENAME=""

# Find most recent xlsx/csv/xls in Downloads
LATEST_FILE=$(find /home/ga/Downloads -type f \( -name "*.xlsx" -o -name "*.csv" -o -name "*.xls" \) -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$LATEST_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$LATEST_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        DOWNLOAD_FOUND="true"
        DOWNLOAD_FILENAME=$(basename "$LATEST_FILE")
    fi
fi

# 4. Check Bookmarks (via sqlite3)
# Kill Firefox to ensure database is flushed/unlocked
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

PROFILE_DIR=$(find /home/ga/.mozilla/firefox -name "*.default*" -type d | head -1)
# Fallback if standard path fails (e.g. snap)
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs dirname)
fi

BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_COUNT=0
URL_VISITED="false"

if [ -f "$PROFILE_DIR/places.sqlite" ]; then
    DB_PATH="$PROFILE_DIR/places.sqlite"
    # Copy DB to temp to avoid lock
    cp "$DB_PATH" /tmp/places_check.sqlite
    
    # Check for "Appliance Procurement" folder
    FOLDER_CHECK=$(sqlite3 /tmp/places_check.sqlite "SELECT id FROM moz_bookmarks WHERE title='Appliance Procurement' AND type=2;")
    if [ -n "$FOLDER_CHECK" ]; then
        BOOKMARK_FOLDER_FOUND="true"
        # Check if it has content (bookmarks inside it)
        BOOKMARK_COUNT=$(sqlite3 /tmp/places_check.sqlite "SELECT count(*) FROM moz_bookmarks WHERE parent=$FOLDER_CHECK AND type=1;")
    fi

    # Check History for energystar.gov
    HISTORY_CHECK=$(sqlite3 /tmp/places_check.sqlite "SELECT count(*) FROM moz_places WHERE url LIKE '%energystar.gov%' AND visit_count > 0;")
    if [ "$HISTORY_CHECK" -gt 0 ]; then
        URL_VISITED="true"
    fi
    
    rm -f /tmp/places_check.sqlite
fi

# 5. Create Result JSON
# Use a temp file to build JSON then move it
TEMP_RESULT=$(mktemp)
cat <<EOF > "$TEMP_RESULT"
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "json_exists": $JSON_EXISTS,
  "json_valid": $JSON_VALID,
  "json_content": $JSON_CONTENT,
  "download_found": $DOWNLOAD_FOUND,
  "download_filename": "$DOWNLOAD_FILENAME",
  "bookmark_folder_found": $BOOKMARK_FOLDER_FOUND,
  "bookmark_count": $BOOKMARK_COUNT,
  "url_visited": $URL_VISITED
}
EOF

# Move to standard location accessible by verifier
cp "$TEMP_RESULT" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json