#!/bin/bash
# export_result.sh - Post-task hook for cpsc_recall_risk_assessment
# Extracts browser history/bookmarks and file metadata for verification

echo "=== Exporting cpsc_recall_risk_assessment results ==="

# 1. Take final screenshot (Visual evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to force flush SQLite WAL (Write-Ahead Log)
# This ensures all recent history/bookmarks are committed to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Retrieve configuration
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000)) # SQLite stores visits in microseconds
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")

# Fallback profile search if setup script failed to save it
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    for candidate in \
        "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
        "/home/ga/.mozilla/firefox/default.profile"; do
        if [ -f "$candidate/places.sqlite" ]; then
            PROFILE_DIR="$candidate"
            break
        fi
    done
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"
echo "Using places.sqlite from: $PLACES_DB"

# 4. Initialize result variables
CPSC_VISITS=0
SAFERPRODUCTS_VISITS=0
BOOKMARK_FOLDER_EXISTS="false"
BOOKMARK_FOLDER_COUNT=0
TOTAL_BOOKMARKS=0
OUTPUT_FILE_EXISTS="false"
OUTPUT_FILE_FRESH="false"
OUTPUT_FILE_SIZE=0

# 5. Analyze Browser Data (History & Bookmarks)
if [ -f "$PLACES_DB" ]; then
    # Force checkpoint to ensure WAL is merged
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Create temp copy to read safely
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check history for cpsc.gov
        CPSC_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%cpsc.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check history for saferproducts.gov
        SAFERPRODUCTS_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
             WHERE p.url LIKE '%saferproducts.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check for specific bookmark folder "Product Safety Research" (case insensitive)
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%product safety research%' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS="true"
            # Count items inside this folder
            BOOKMARK_FOLDER_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
        fi
        
        # Total bookmarks
        TOTAL_BOOKMARKS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1;" 2>/dev/null || echo "0")
        
        rm -f "$TEMP_DB"
    fi
fi

# 6. Analyze Output File Metadata
OUTPUT_PATH="/home/ga/Documents/cpsc_risk_assessment.json"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify file was modified AFTER task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_FILE_FRESH="true"
    fi
fi

# 7. Generate JSON Summary
# This file summarizes system state for the verifier
# The actual content of the user's JSON file will be read directly by the verifier using copy_from_env

SUMMARY_JSON=$(mktemp /tmp/summary.XXXXXX.json)
cat > "$SUMMARY_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "cpsc_visits": $CPSC_VISITS,
    "saferproducts_visits": $SAFERPRODUCTS_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmark_folder_count": $BOOKMARK_FOLDER_COUNT,
    "total_bookmarks": $TOTAL_BOOKMARKS,
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_file_fresh": $OUTPUT_FILE_FRESH,
    "output_file_size": $OUTPUT_FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with relaxed permissions
mv "$SUMMARY_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export summary saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="