#!/bin/bash
# export_result.sh - Post-task hook for component_sourcing_research

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# 3. Gather Paths and Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

JSON_PATH="/home/ga/Documents/bom_report.json"
PDF_PATH="/home/ga/Documents/NE555P_datasheet.pdf"

# 4. Check Files
JSON_EXISTS=0
JSON_FRESH=0
JSON_CONTENT="{}"
if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS=1
    MTIME=$(stat -c %Y "$JSON_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH=1
    fi
    # Read content for verifier (safe reading)
    JSON_CONTENT=$(cat "$JSON_PATH")
fi

PDF_EXISTS=0
PDF_FRESH=0
PDF_SIZE=0
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS=1
    MTIME=$(stat -c %Y "$PDF_PATH")
    SIZE=$(stat -c %s "$PDF_PATH")
    PDF_SIZE=$SIZE
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PDF_FRESH=1
    fi
fi

# 5. Check Browser Data (History & Bookmarks)
DIGIKEY_VISITS=0
BOM_FOLDER_EXISTS=0
BOM_FOLDER_COUNT=0
TOTAL_BOOKMARKS=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy to temp to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB"
    
    # Check History for digikey product pages
    DIGIKEY_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%digikey.com/en/products/detail%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check for 'BOM Research' folder
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='BOM Research';" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOM_FOLDER_EXISTS=1
        # Count bookmarks inside this folder
        BOM_FOLDER_COUNT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi

    TOTAL_BOOKMARKS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
    
    rm -f "$TEMP_DB"
fi

# 6. Create Result JSON
# We use python to safely construct the JSON to avoid escaping issues with the file content
python3 <<EOF
import json
import os

result = {
    "task_start": $TASK_START,
    "json_exists": bool($JSON_EXISTS),
    "json_fresh": bool($JSON_FRESH),
    "json_content": """$JSON_CONTENT""",
    "pdf_exists": bool($PDF_EXISTS),
    "pdf_fresh": bool($PDF_FRESH),
    "pdf_size_bytes": $PDF_SIZE,
    "digikey_visits": $DIGIKEY_VISITS,
    "bom_folder_exists": bool($BOM_FOLDER_EXISTS),
    "bom_folder_count": $BOM_FOLDER_COUNT,
    "total_bookmarks": $TOTAL_BOOKMARKS
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/task_result.json"