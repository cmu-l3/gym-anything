#!/bin/bash
# export_result.sh - Post-task hook for hr_occupational_license_compliance

echo "=== Exporting task results ==="

# 1. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Timing Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_START_US=$((TASK_START * 1000000))

# 3. File Verification (JSON Report)
REPORT_PATH="/home/ga/Documents/pt_licensing_audit.json"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT="{}"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_PATH")
fi

# 4. Firefox Data Verification (History & Bookmarks)
# Kill Firefox to flush WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)
if [ -z "$PROFILE_DIR" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi

HISTORY_MATCH_COUNT=0
BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_LINKS_COUNT=0
BOOKMARKS_IN_FOLDER=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Copy DB to temp to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite
    
    # Check History for CareerOneStop
    HISTORY_MATCH_COUNT=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%careeronestop.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check for 'State Boards' bookmark folder
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title='State Boards';" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_FOUND="true"
        # Count bookmarks inside this folder
        BOOKMARKS_IN_FOLDER=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
        
        # Verify bookmarks look like CareerOneStop links (optional quality check)
        BOOKMARK_LINKS_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
             WHERE b.parent=$FOLDER_ID AND p.url LIKE '%careeronestop.org%';" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_CREATED_DURING_TASK,
    "history_hits": $HISTORY_MATCH_COUNT,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_FOUND,
    "bookmarks_in_folder": $BOOKMARKS_IN_FOLDER,
    "valid_bookmarks_count": $BOOKMARK_LINKS_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Append the report content as a nested JSON string or object
# We use python to safely merge the report content into the result JSON to avoid shell escaping hell
python3 -c "
import json
import sys

try:
    with open('$TEMP_JSON', 'r') as f:
        data = json.load(f)
    
    report_content_str = '''$REPORT_CONTENT'''
    try:
        if data['report_exists']:
            data['report_content'] = json.loads(report_content_str)
        else:
            data['report_content'] = None
    except json.JSONDecodeError:
        data['report_content'] = 'INVALID_JSON'
        
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f'Error processing JSON: {e}')
"

# Clean up
rm -f "$TEMP_JSON"
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"