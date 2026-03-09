#!/bin/bash
# export_result.sh - Post-task hook for hts_tariff_classification

echo "=== Exporting HTS Tariff Classification Results ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Prepare timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_START_US=$((TASK_START * 1000000))

# 3. Flush Firefox data
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 4. Analyze Firefox History & Bookmarks
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)
PLACES_DB="$PROFILE_DIR/places.sqlite"

HTS_VISITS=0
TRADE_BM_FOLDER_EXISTS="false"
TRADE_BM_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Use a temp copy to avoid locks
    cp "$PLACES_DB" /tmp/places_export.sqlite
    
    # Check visits to USITC HTS
    HTS_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%hts.usitc.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check for Bookmark Folder "Trade Compliance"
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Trade Compliance';" 2>/dev/null)
        
    if [ -n "$FOLDER_ID" ]; then
        TRADE_BM_FOLDER_EXISTS="true"
        # Count bookmarks in that folder
        TRADE_BM_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 5. Check Output File
OUTPUT_FILE="/home/ga/Documents/tariff_classification.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
    
    # Read content safely (escape for JSON embedding if needed, but we'll cat it into a python script or similar usually. 
    # Here we will let the python verifier read the file directly via copy_from_env, 
    # but for redundancy we can dump a snippet).
    # We will assume the verifier pulls the actual file.
fi

# 6. Create JSON result for Verifier
# We will copy the output file separately, but this metadata JSON helps the verifier know about browser state.
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "hts_visits": $HTS_VISITS,
  "bookmark_folder_exists": $TRADE_BM_FOLDER_EXISTS,
  "bookmark_count": $TRADE_BM_COUNT,
  "file_exists": $FILE_EXISTS,
  "file_fresh": $FILE_FRESH,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Ensure permissions for copy_from_env
chmod 644 /tmp/task_result.json
chmod 644 "$OUTPUT_FILE" 2>/dev/null || true

echo "Export complete. Results saved to /tmp/task_result.json"