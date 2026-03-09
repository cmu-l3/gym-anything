#!/bin/bash
# export_result.sh - Post-task hook for SRE DNS & SSL Audit
set -e

echo "=== Exporting SRE DNS & SSL Audit results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Context info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Analyze Firefox History & Bookmarks
PLACES_DB="$PROFILE_DIR/places.sqlite"
TOOL_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_COUNT_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Create temp copy
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    # Check History for required tools
    TOOL_VISITS=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE (p.url LIKE '%toolbox.googleapps.com%' OR p.url LIKE '%sslshopper.com%' OR p.url LIKE '%digicert.com%') 
         AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
         
    # Check for Bookmark Folder "Incident 2411 Audit"
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Incident 2411 Audit' LIMIT 1;" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_EXISTS="true"
        # Count bookmarks inside that folder
        BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=${FOLDER_ID};" 2>/dev/null || echo "0")
    fi
    
    rm -f "$TEMP_DB"
fi

# 5. Analyze Output File (audit_log.json)
OUTPUT_FILE="/home/ga/Documents/audit_log.json"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content safely
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
fi

# 6. Create Result JSON
# Using python to safely generate JSON to avoid quoting issues
python3 << EOF
import json
import os

result = {
    "tool_visits": $TOOL_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_count_in_folder": $BOOKMARK_COUNT_IN_FOLDER,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_str": """$FILE_CONTENT"""
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"