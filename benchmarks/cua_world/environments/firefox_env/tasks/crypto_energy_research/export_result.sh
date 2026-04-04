#!/bin/bash
# export_result.sh - Post-task hook for crypto_energy_research

echo "=== Exporting crypto_energy_research results ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to ensure SQLite WAL is flushed
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Context
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
# Convert to microseconds for Firefox history timestamp comparison
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)

if [ -z "$PROFILE_DIR" ]; then
    # Try to find it again if setup failed to record it
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

echo "Using DB: $PLACES_DB"

# 4. Query Firefox Database (History & Bookmarks)
# Initialize variables
HISTORY_EIA=0
HISTORY_EPA=0
HISTORY_WH=0
HISTORY_IEA=0
BM_FOLDER_FOUND="false"
BM_COUNT_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Create temp copy
    cp "$PLACES_DB" /tmp/places_export.sqlite
    
    # Check History (visits after task start)
    HISTORY_EIA=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%eia.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
        
    HISTORY_EPA=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%epa.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
        
    HISTORY_WH=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%whitehouse.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    HISTORY_IEA=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%iea.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmarks Folder "Crypto Environmental Research"
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Crypto Environmental Research' LIMIT 1;" 2>/dev/null)
        
    if [ -n "$FOLDER_ID" ]; then
        BM_FOLDER_FOUND="true"
        # Count bookmarks inside this folder
        BM_COUNT_IN_FOLDER=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 5. Check JSON Output File
JSON_FILE="/home/ga/Documents/crypto_environmental_brief.json"
JSON_EXISTS="false"
JSON_FRESH="false"
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_FRESH="true"
    fi
fi

# 6. Check Downloaded PDF
# Look for any PDF in Downloads created after task start and size > 10KB
PDF_FOUND="false"
PDF_NAME=""
for f in /home/ga/Downloads/*.pdf /home/ga/Downloads/*.PDF; do
    [ -e "$f" ] || continue
    F_MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
    F_SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
    
    # Check if new and > 10KB (10240 bytes)
    if [ "$F_MTIME" -gt "$TASK_START" ] && [ "$F_SIZE" -gt 10240 ]; then
        PDF_FOUND="true"
        PDF_NAME=$(basename "$f")
        break
    fi
done

# 7. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "history_stats": {
        "eia": $HISTORY_EIA,
        "epa": $HISTORY_EPA,
        "whitehouse": $HISTORY_WH,
        "iea": $HISTORY_IEA
    },
    "bookmarks": {
        "folder_found": $BM_FOLDER_FOUND,
        "count": $BM_COUNT_IN_FOLDER
    },
    "json_file": {
        "exists": $JSON_EXISTS,
        "fresh": $JSON_FRESH,
        "path": "$JSON_FILE"
    },
    "download": {
        "pdf_found": $PDF_FOUND,
        "filename": "$PDF_NAME"
    },
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON created at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="