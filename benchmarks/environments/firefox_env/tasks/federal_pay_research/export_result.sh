#!/bin/bash
# export_result.sh - Post-task hook for federal_pay_research

echo "=== Exporting federal_pay_research results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Prepare result variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
OUTPUT_FILE="/home/ga/Documents/federal_pay_comparison.json"

# 3. Check JSON report file status
REPORT_EXISTS="false"
REPORT_FRESH="false"
REPORT_CONTENT=""
if [ -f "$OUTPUT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
    # Read content safely (max 10KB to prevent bloat)
    REPORT_CONTENT=$(head -c 10000 "$OUTPUT_FILE")
fi

# 4. Flush Firefox WAL
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 5. Analyze Browser History & Bookmarks
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search if path lost
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

OPM_VISITS=0
USAJOBS_VISITS=0
FOLDER_EXISTS="false"
BOOKMARK_COUNT=0
CORRECT_URLS=0

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    # Use temp DB to avoid locks
    cp "$PROFILE_DIR/places.sqlite" /tmp/places_export.sqlite 2>/dev/null
    
    # History Check
    OPM_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%opm.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    USAJOBS_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%usajobs.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
    
    # Bookmark Check
    # Find folder id for "Federal Employment Research" (case-insensitive)
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%federal employment research%' LIMIT 1;" 2>/dev/null || echo "")
        
    if [ -n "$FOLDER_ID" ]; then
        FOLDER_EXISTS="true"
        # Count bookmarks in that folder
        BOOKMARK_COUNT=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=$FOLDER_ID;" 2>/dev/null || echo "0")
            
        # Count relevant URLs in that folder (opm or usajobs)
        CORRECT_URLS=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id 
             WHERE b.type=1 AND b.parent=$FOLDER_ID 
             AND (p.url LIKE '%opm.gov%' OR p.url LIKE '%usajobs.gov%');" 2>/dev/null || echo "0")
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 6. Create clean JSON result
# We use Python to write the JSON to ensure proper escaping of the report content
python3 << EOF
import json
import os

result = {
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "opm_visits": $OPM_VISITS,
    "usajobs_visits": $USAJOBS_VISITS,
    "folder_exists": $FOLDER_EXISTS,
    "bookmark_count": $BOOKMARK_COUNT,
    "correct_urls_count": $CORRECT_URLS,
    "screenshot_path": "/tmp/task_final.png"
}

# Try to parse the report content as JSON if it exists
report_content = """$REPORT_CONTENT"""
try:
    if report_content:
        result["report_data"] = json.loads(report_content)
        result["report_valid_json"] = True
    else:
        result["report_data"] = {}
        result["report_valid_json"] = False
except Exception as e:
    result["report_data"] = {}
    result["report_valid_json"] = False
    result["json_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# 7. Secure result file
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/task_result.json"