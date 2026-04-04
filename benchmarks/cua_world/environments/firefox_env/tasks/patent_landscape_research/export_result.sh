#!/bin/bash
# export_result.sh - Post-task hook for patent_landscape_research

echo "=== Exporting Patent Landscape Research results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush WAL to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 4. Locate Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
# Fallback if setup didn't save it or it's gone
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

# 5. Analyze Firefox Data (History & Bookmarks)
HISTORY_VISITS_GOOGLE=0
HISTORY_VISITS_USPTO=0
FOLDER_EXISTS=0
FOLDER_ID=""
BOOKMARK_COUNT=0
BOOKMARK_URLS=""

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy to temp to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB"
    
    # Check History
    HISTORY_VISITS_GOOGLE=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%patents.google.com%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
    
    HISTORY_VISITS_USPTO=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE (p.url LIKE '%uspto.gov%' OR p.url LIKE '%espacenet.com%') AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmark Folder "Patent Landscape Research"
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Patent Landscape Research' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        FOLDER_EXISTS=1
        # Count bookmarks in that folder
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        
        # Get URLs of bookmarks in that folder (newline separated)
        BOOKMARK_URLS=$(sqlite3 "$TEMP_DB" \
            "SELECT p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.parent=$FOLDER_ID AND b.type=1;" 2>/dev/null || echo "")
    fi
    
    rm -f "$TEMP_DB"
fi

# 6. Check JSON Report
REPORT_PATH="/home/ga/Documents/patent_landscape.json"
REPORT_EXISTS=0
REPORT_FRESH=0
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH=1
    fi
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# Use Python to generate JSON to avoid escaping issues with URLs
python3 << EOF > "$TEMP_JSON"
import json
import os

data = {
    "history_google_patents": $HISTORY_VISITS_GOOGLE,
    "history_uspto": $HISTORY_VISITS_USPTO,
    "bookmark_folder_exists": bool($FOLDER_EXISTS),
    "bookmark_count_in_folder": $BOOKMARK_COUNT,
    "bookmark_urls": """$BOOKMARK_URLS""".splitlines(),
    "report_exists": bool($REPORT_EXISTS),
    "report_fresh": bool($REPORT_FRESH),
    "report_size": $REPORT_SIZE,
    "task_start_time": $TASK_START
}

print(json.dumps(data))
EOF

# Move to final location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"