#!/bin/bash
# export_result.sh - Post-task hook for eia_state_energy_analysis

echo "=== Exporting EIA Task Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Kill Firefox to flush SQLite Write-Ahead Log (WAL) to the main database file
echo "Flushing Firefox database..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Load task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Locate Firefox profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search if temp file missing
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

echo "Analyzing database: $PLACES_DB"

# Initialize variables
GRID_FOLDER_EXISTS="false"
GRID_FOLDER_ID=""
BOOKMARK_COUNT=0
EIA_VISITS=0
TX_VISIT="false"
CA_VISIT="false"
WV_VISIT="false"

if [ -f "$PLACES_DB" ]; then
    # Create temp copy to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null

    if [ -f "$TEMP_DB" ]; then
        # 1. Check for 'Grid Analysis' bookmark folder
        GRID_FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title)='grid analysis' LIMIT 1;" 2>/dev/null || echo "")
        
        if [ -n "$GRID_FOLDER_ID" ]; then
            GRID_FOLDER_EXISTS="true"
            # Count bookmarks to eia.gov inside this folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
                 WHERE b.parent=$GRID_FOLDER_ID AND b.type=1 AND p.url LIKE '%eia.gov%';" 2>/dev/null || echo "0")
        fi

        # 2. Check History for state pages
        EIA_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%eia.gov/state%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
        
        # Check specific state codes in URLs (TX, CA, WV)
        # Note: EIA URLs are typically eia.gov/state/?sid=TX
        TX_VISIT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%sid=TX%' OR p.title LIKE '%Texas%') AND p.url LIKE '%eia.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null | grep -q "0" && echo "false" || echo "true")
        
        CA_VISIT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%sid=CA%' OR p.title LIKE '%California%') AND p.url LIKE '%eia.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null | grep -q "0" && echo "false" || echo "true")
            
        WV_VISIT=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%sid=WV%' OR p.title LIKE '%West Virginia%') AND p.url LIKE '%eia.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null | grep -q "0" && echo "false" || echo "true")

        rm -f "$TEMP_DB"
    fi
fi

# 3. Check Output JSON File
OUTPUT_FILE="/home/ga/Documents/energy_comparison.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "grid_folder_exists": $GRID_FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "eia_visits_total": $EIA_VISITS,
    "visited_tx": $TX_VISIT,
    "visited_ca": $CA_VISIT,
    "visited_wv": $WV_VISIT,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="