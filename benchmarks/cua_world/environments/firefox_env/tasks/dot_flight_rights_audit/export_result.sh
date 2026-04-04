#!/bin/bash
# export_result.sh - Post-task hook for dot_flight_rights_audit

echo "=== Exporting dot_flight_rights_audit results ==="

# 1. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush WAL to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search if variable lost
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 4. Check Browser History (DOT visits)
DOT_VISITS=0
if [ -f "$PLACES_DB" ]; then
    # Checkpoint to ensure data is in main DB
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_export.sqlite
    
    DOT_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%transportation.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check Bookmarks
    # 1. Find folder "Travel Policy Resources"
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Travel Policy Resources' LIMIT 1;" 2>/dev/null || echo "")
        
    FOLDER_EXISTS="false"
    BOOKMARKS_IN_FOLDER=0
    
    if [ -n "$FOLDER_ID" ]; then
        FOLDER_EXISTS="true"
        # Count bookmarks inside this folder
        BOOKMARKS_IN_FOLDER=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 5. Check JSON Output
JSON_FILE="/home/ga/Documents/airline_rights_audit.json"
JSON_EXISTS="false"
JSON_CONTENT="{}"
JSON_FRESH="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    # Check freshness
    F_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$F_MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH="true"
    fi
    # Read content safely
    JSON_CONTENT=$(cat "$JSON_FILE")
fi

# 6. Check PDF Download
# Look for any PDF in Downloads created after task start, size > 50KB
PDF_FOUND="false"
PDF_SIZE=0
PDF_NAME=""

# Find relevant PDF files
FOUND_PDFS=$(find /home/ga/Downloads -name "*.pdf" -newermt "@$TASK_START" 2>/dev/null)

for pdf in $FOUND_PDFS; do
    SIZE=$(stat -c %s "$pdf")
    if [ "$SIZE" -gt 50000 ]; then
        PDF_FOUND="true"
        PDF_SIZE=$SIZE
        PDF_NAME=$(basename "$pdf")
        break
    fi
done

# 7. Construct Result JSON
# We use Python to robustly construct the JSON to avoid quoting issues with the captured file content
python3 <<EOF
import json
import os

result = {
    "task_start": $TASK_START,
    "dot_visits": $DOT_VISITS,
    "folder_exists": $FOLDER_EXISTS,
    "bookmarks_in_folder": $BOOKMARKS_IN_FOLDER,
    "json_exists": $JSON_EXISTS,
    "json_fresh": $JSON_FRESH,
    "json_content_str": """$JSON_CONTENT""",
    "pdf_found": $PDF_FOUND,
    "pdf_size": $PDF_SIZE,
    "pdf_name": "$PDF_NAME"
}

# Try to parse the captured content string as JSON object for nested verification
try:
    if result["json_exists"]:
        result["json_data"] = json.loads(result["json_content_str"])
    else:
        result["json_data"] = None
except:
    result["json_data"] = None

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

echo "Export complete. Result saved to /tmp/task_result.json"