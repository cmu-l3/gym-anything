#!/bin/bash
# export_result.sh - Post-task hook for nrel_pvwatts_solar_estimate

echo "=== Exporting NREL PVWatts Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get timing data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
CURRENT_TIME=$(date +%s)

# 3. Check for Report File
REPORT_PATH="/home/ga/Documents/solar_production_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_FRESH="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Limit size
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
fi

# 4. Check for Downloaded CSV
# NREL typically names files like "pvwatts_hourly.csv" or "pvwatts_hourly (1).csv"
CSV_PATH=$(find /home/ga/Downloads -name "pvwatts_hourly*.csv" -newer /tmp/task_start_time.txt 2>/dev/null | head -n 1)
CSV_EXISTS="false"
CSV_SIZE="0"

if [ -n "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 5. Check Bookmarks & History via SQLite
# Need to copy DB first because Firefox locks it
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
# Fallback search if tmp file missing
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
fi

BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_LINK_FOUND="false"
HISTORY_FOUND="false"

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Flush WAL (checkpoint) if possible, or just copy and hope
    # Best practice: kill firefox to flush, but that might disturb state. 
    # We will copy to temp.
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB"
    
    if [ -f "$TEMP_DB" ]; then
        # Check for Folder "Client Estimates"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" "SELECT id FROM moz_bookmarks WHERE title='Client Estimates' AND type=2 LIMIT 1;" 2>/dev/null)
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_FOUND="true"
            # Check for link inside folder
            LINK_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.parent=$FOLDER_ID AND p.url LIKE '%nrel.gov%';" 2>/dev/null || echo "0")
            if [ "$LINK_COUNT" -gt "0" ]; then
                BOOKMARK_LINK_FOUND="true"
            fi
        fi
        
        # Check History for pvwatts.nrel.gov visited AFTER task start
        # moz_historyvisits stores time in microseconds
        HISTORY_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%pvwatts.nrel.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
        if [ "$HISTORY_COUNT" -gt "0" ]; then
            HISTORY_FOUND="true"
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Create JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "bookmark_folder_found": $BOOKMARK_FOLDER_FOUND,
    "bookmark_link_found": $BOOKMARK_LINK_FOUND,
    "history_found": $HISTORY_FOUND,
    "task_start": $TASK_START,
    "timestamp": $CURRENT_TIME
}
EOF

# 7. Safe move to final location
rm -f /tmp/nrel_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/nrel_task_result.json
chmod 666 /tmp/nrel_task_result.json
rm "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/nrel_task_result.json"
cat /tmp/nrel_task_result.json