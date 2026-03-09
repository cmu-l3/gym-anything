#!/bin/bash
# export_result.sh - Post-task hook for fema_disaster_history

echo "=== Exporting fema_disaster_history results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Close Firefox to flush databases (WAL files)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read setup variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
INITIAL_BOOKMARKS=$(cat /tmp/initial_bookmark_count 2>/dev/null || echo "0")

# 4. Check JSON Output
JSON_FILE="/home/ga/Documents/california_fire_history.json"
JSON_EXISTS=0
JSON_VALID=0
JSON_CONTENT=""

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS=1
    # Basic valid check
    if jq . "$JSON_FILE" >/dev/null 2>&1; then
        JSON_VALID=1
        JSON_CONTENT=$(cat "$JSON_FILE")
    fi
fi

# 5. Check Downloads
# Look for any PDF downloaded after task start
DOWNLOADED_PDF_EXISTS=0
DOWNLOADED_PDF_NAME=""
DOWNLOADED_PDF_SIZE=0

# Find files in Downloads ending in .pdf modified after task start
PDF_FILE=$(find /home/ga/Downloads -name "*.pdf" -newermt "@$TASK_START" 2>/dev/null | head -n 1)

if [ -n "$PDF_FILE" ]; then
    DOWNLOADED_PDF_EXISTS=1
    DOWNLOADED_PDF_NAME=$(basename "$PDF_FILE")
    DOWNLOADED_PDF_SIZE=$(stat -c%s "$PDF_FILE")
fi

# 6. Check Browser History & Bookmarks
HISTORY_VISITS_FEMA=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARK_COUNT_IN_FOLDER=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite

    # Check History: Visits to fema.gov/disaster
    HISTORY_VISITS_FEMA=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%fema.gov/disaster%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmarks: Folder "FEMA Research"
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE title='FEMA Research' AND type=2;" 2>/dev/null || echo "")

    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS=1
        # Count bookmarks inside this folder
        BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi

    rm -f /tmp/places_export.sqlite
fi

# 7. Construct Result JSON
# Use a temp file to avoid quoting hell
cat > /tmp/task_result.json <<EOF
{
  "json_exists": $JSON_EXISTS,
  "json_valid": $JSON_VALID,
  "downloaded_pdf_exists": $DOWNLOADED_PDF_EXISTS,
  "downloaded_pdf_name": "$DOWNLOADED_PDF_NAME",
  "downloaded_pdf_size": $DOWNLOADED_PDF_SIZE,
  "history_fema_visits": $HISTORY_VISITS_FEMA,
  "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
  "bookmark_count_in_folder": $BOOKMARK_COUNT_IN_FOLDER,
  "task_start_time": $TASK_START
}
EOF

# Append the actual JSON content if it's valid (using jq to insert it safely)
if [ "$JSON_VALID" -eq 1 ]; then
    # We need to read the file content into a variable safely
    jq --slurpfile content "$JSON_FILE" '. + {json_content: $content[0]}' /tmp/task_result.json > /tmp/task_result.json.tmp && mv /tmp/task_result.json.tmp /tmp/task_result.json
fi

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json