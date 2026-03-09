#!/bin/bash
# export_result.sh - Post-task hook for icd10_clinical_coding

set -e
echo "=== Exporting ICD-10 Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Stop Firefox to flush WAL to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Gather Timing Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))
EXPORT_TIME=$(date +%s)

# 4. Check Output File Status
OUTPUT_FILE="/home/ga/Documents/icd10_coding_sheet.json"
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 5. Analyze Firefox History & Bookmarks
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null)
PLACES_DB="$PROFILE_DIR/places.sqlite"

HISTORY_HITS_WHO=0
HISTORY_HITS_ICDDATA=0
HISTORY_HITS_CMS=0
BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_COUNT_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to read safely
    cp "$PLACES_DB" /tmp/places_export.sqlite
    
    # Check History (visits after task start)
    HISTORY_HITS_WHO=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%who.int%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
    
    HISTORY_HITS_ICDDATA=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%icd10data.com%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
        
    HISTORY_HITS_CMS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%cms.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check Bookmarks
    # Find folder id for "Medical Coding Resources" (type=2 is folder)
    FOLDER_ID=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE '%Medical Coding Resources%' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_FOUND="true"
        # Count bookmarks (type=1) in that folder
        BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 /tmp/places_export.sqlite \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=$FOLDER_ID;" 2>/dev/null || echo "0")
    fi

    rm -f /tmp/places_export.sqlite
fi

# 6. Create Result JSON
# We do NOT cat the content of the output file here to avoid JSON escaping issues in bash.
# The verifier will read the output file directly via copy_from_env.
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "export_time": $EXPORT_TIME,
  "file_exists": $FILE_EXISTS,
  "file_fresh": $FILE_FRESH,
  "file_size": $FILE_SIZE,
  "history_hits": {
    "who": $HISTORY_HITS_WHO,
    "icd10data": $HISTORY_HITS_ICDDATA,
    "cms": $HISTORY_HITS_CMS
  },
  "bookmarks": {
    "folder_found": $BOOKMARK_FOLDER_FOUND,
    "count_in_folder": $BOOKMARK_COUNT_IN_FOLDER
  }
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json