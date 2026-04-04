#!/bin/bash
# export_result.sh - Post-task hook for OFAC Sanctions Compliance Screening

echo "=== Exporting OFAC Task Results ==="

# 1. Capture Final Screenshot (Visual Proof)
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# 2. Stop Firefox (Force flush of SQLite WAL to disk)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Load Environment Variables
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
# Convert to microseconds for Mozilla timestamp comparison
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# 4. Check Browser State (History & Bookmarks)
HISTORY_VISITS=0
BOOKMARK_FOLDER_FOUND=false
BOOKMARK_COUNT=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Create a temp copy of the DB to read safely
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite 2>/dev/null
    
    if [ -f /tmp/places_export.sqlite ]; then
        # Check History: Did they visit the OFAC search tool?
        # Looking for 'treas.gov' or 'sanctionssearch' in URL
        HISTORY_VISITS=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE (p.url LIKE '%treas.gov%' OR p.url LIKE '%sanctionssearch%') 
             AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        # Check Bookmarks: Look for folder "Compliance Tools"
        FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Compliance Tools';" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_FOUND=true
            # Count bookmarks inside this folder
            BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f /tmp/places_export.sqlite
    fi
fi

# 5. Check Output File
REPORT_FILE="/home/ga/Documents/sanctions_audit.json"
FILE_EXISTS=false
FILE_FRESH=false
FILE_CONTENT="{}"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=true
    fi
    
    # Read content if it's valid JSON
    if jq . "$REPORT_FILE" >/dev/null 2>&1; then
        FILE_CONTENT=$(cat "$REPORT_FILE")
    else
        # If invalid JSON, read as raw string but wrapped in JSON for transport
        RAW_CONTENT=$(cat "$REPORT_FILE" | sed 's/"/\\"/g' | tr -d '\n')
        FILE_CONTENT="{\"error\": \"Invalid JSON\", \"raw\": \"$RAW_CONTENT\"}"
    fi
fi

# 6. Construct JSON Result
# Using a temp file to ensure atomic write and proper formatting
cat > /tmp/task_result.json <<EOF
{
  "task_start_time": $TASK_START,
  "history_visits": $HISTORY_VISITS,
  "bookmark_folder_found": $BOOKMARK_FOLDER_FOUND,
  "bookmark_count": $BOOKMARK_COUNT,
  "file_exists": $FILE_EXISTS,
  "file_fresh": $FILE_FRESH,
  "file_path": "$REPORT_FILE",
  "file_content": $FILE_CONTENT
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"