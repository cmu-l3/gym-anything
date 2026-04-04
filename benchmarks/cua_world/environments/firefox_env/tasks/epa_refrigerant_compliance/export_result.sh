#!/bin/bash
# export_result.sh - Post-task hook for EPA Refrigerant Compliance Research

echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Locate Firefox Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path.txt 2>/dev/null)
if [ -z "$PROFILE_DIR" ]; then
     # Try to find it again if setup script failed to save it
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

echo "Using Places DB: $PLACES_DB"

# 4. Extract History and Bookmarks
# We copy the DB to temp to avoid locking issues while Firefox is running
TEMP_DB="/tmp/places_export.sqlite"
cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null

HISTORY_JSON="[]"
BOOKMARKS_JSON="[]"

if [ -f "$TEMP_DB" ]; then
    # Extract History (Visits after task start)
    # Convert TASK_START to microseconds (PRTime)
    TASK_START_US=$((TASK_START * 1000000))
    
    # Get distinct URLs visited
    HISTORY_QUERY="SELECT p.url FROM moz_places p JOIN moz_historyvisits h ON p.id = h.place_id WHERE h.visit_date >= $TASK_START_US GROUP BY p.url;"
    HISTORY_LIST=$(sqlite3 "$TEMP_DB" "$HISTORY_QUERY")
    
    # Format as JSON array manually or using jq if available, falling back to python
    HISTORY_JSON=$(echo "$HISTORY_LIST" | python3 -c 'import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')

    # Extract Bookmarks
    # Get title and url of bookmarks
    BOOKMARKS_QUERY="SELECT b.title, p.url, (SELECT title FROM moz_bookmarks WHERE id=b.parent) as folder_name FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1;"
    # We output line-delimited JSON objects then slurp them
    BOOKMARKS_JSON=$(sqlite3 "$TEMP_DB" -json "$BOOKMARKS_QUERY" 2>/dev/null || echo "[]")
    
    rm "$TEMP_DB"
fi

# 5. Check Output File
OUTPUT_FILE="/home/ga/Documents/refrigerant_compliance_guide.json"
FILE_EXISTS="false"
FILE_MTIME=0
FILE_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    # Read content if valid JSON
    if jq . "$OUTPUT_FILE" >/dev/null 2>&1; then
        FILE_CONTENT=$(cat "$OUTPUT_FILE")
    else
        # If invalid JSON, read as string but escape it carefully or just note it's invalid
        FILE_CONTENT="null" 
    fi
fi

# 6. Create Result JSON
# We use a python script to construct the final JSON to avoid bash quoting hell
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': $FILE_EXISTS,
    'file_mtime': $FILE_MTIME,
    'file_content': $FILE_CONTENT if $FILE_EXISTS and '$FILE_CONTENT' != 'null' else None,
    'history': $HISTORY_JSON,
    'bookmarks': $BOOKMARKS_JSON if '$BOOKMARKS_JSON' else []
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# 7. Set permissions so the host can copy it
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png

echo "Export complete. Result saved to /tmp/task_result.json"