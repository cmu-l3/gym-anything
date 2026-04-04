#!/bin/bash
# export_result.sh - Post-task hook for scotus_case_law_research
set -e

echo "=== Exporting SCOTUS Research Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL (Write-Ahead Log)
# Crucial for accurate bookmark/history reading
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# 3. Read Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 4. Locate Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ]; then
    # Fallback search if tmp file missing
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 5. Analyze Browser Data (History & Bookmarks)
HISTORY_MATCH=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARK_COUNT=0
BOOKMARK_URLS=""

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check History for legal sites
    HISTORY_MATCH=$(sqlite3 "$TEMP_DB" "
        SELECT COUNT(*) FROM moz_historyvisits h 
        JOIN moz_places p ON h.place_id=p.id 
        WHERE (p.url LIKE '%oyez.org%' OR p.url LIKE '%justia.com%' OR p.url LIKE '%cornell.edu%' OR p.url LIKE '%supremecourt.gov%')
        AND h.visit_date > $TASK_START_US;
    " 2>/dev/null || echo "0")

    # Check for 'Constitutional Law' folder
    FOLDER_ID=$(sqlite3 "$TEMP_DB" "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Constitutional Law' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS=1
        # Count bookmarks inside that folder
        BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        
        # Get URLs for debugging/verification
        BOOKMARK_URLS=$(sqlite3 "$TEMP_DB" "
            SELECT p.url FROM moz_bookmarks b 
            JOIN moz_places p ON b.fk=p.id 
            WHERE b.parent=$FOLDER_ID;
        " 2>/dev/null | tr '\n' ',' || echo "")
    fi
    
    rm -f "$TEMP_DB"
fi

# 6. Analyze Output File
OUTPUT_FILE="/home/ga/Documents/scotus_brief.json"
FILE_EXISTS=0
FILE_FRESH=0
FILE_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_FRESH=1
    fi
    # Read content safely
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
fi

# 7. Create Result JSON
# Use Python to ensure valid JSON structure for the exported file content
python3 << EOF
import json
import sys

try:
    file_content_obj = json.loads('''$FILE_CONTENT''')
except:
    file_content_obj = {}

result = {
    "history_hits": $HISTORY_MATCH,
    "bookmark_folder_exists": bool($BOOKMARK_FOLDER_EXISTS),
    "bookmark_count": $BOOKMARK_COUNT,
    "bookmark_urls": "$BOOKMARK_URLS",
    "file_exists": bool($FILE_EXISTS),
    "file_fresh": bool($FILE_FRESH),
    "file_content": file_content_obj
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# 8. Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"