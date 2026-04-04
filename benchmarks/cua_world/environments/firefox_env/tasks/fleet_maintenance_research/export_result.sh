#!/bin/bash
# Export script for fleet_maintenance_research

set -e

echo "=== Exporting Fleet Maintenance Research Results ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# 2. Kill Firefox (to flush SQLite WAL files)
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# 3. Gather Data
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)
OUTPUT_FILE="/home/ga/Documents/fleet_specs.json"

# Check Output File Status
FILE_EXISTS=false
FILE_FRESH=false
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_FRESH=true
    fi
fi

# 4. Analyze Bookmarks & History (using sqlite3)
# We look for RockAuto history and the "Fleet Parts" folder
ROCKAUTO_VISITS=0
FLEET_FOLDER_EXISTS=false
FLEET_FOLDER_COUNT=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Create temp copy to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite
    
    # Check History (RockAuto visits after task start)
    # Convert task start to microseconds (Mozilla format)
    TASK_START_US=$((TASK_START * 1000000))
    
    ROCKAUTO_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%rockauto.com%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check Bookmarks
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Fleet Parts';" 2>/dev/null)
        
    if [ -n "$FOLDER_ID" ]; then
        FLEET_FOLDER_EXISTS=true
        FLEET_FOLDER_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 5. Read the Output JSON Content (safely)
JSON_CONTENT="{}"
if [ "$FILE_EXISTS" = true ]; then
    # Validate JSON first
    if jq empty "$OUTPUT_FILE" 2>/dev/null; then
        JSON_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# 6. Create Result JSON
# We embed the user's JSON content inside our result JSON for the python verifier
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "rockauto_visits": $ROCKAUTO_VISITS,
    "fleet_folder_exists": $FLEET_FOLDER_EXISTS,
    "fleet_folder_count": $FLEET_FOLDER_COUNT,
    "user_json_content": $JSON_CONTENT
}
EOF

# 7. Permission cleanup
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"