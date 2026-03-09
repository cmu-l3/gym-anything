#!/bin/bash
# export_result.sh - Post-task hook for ecfr_water_quality_research

echo "=== Exporting ecfr_water_quality_research results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush WAL to main database
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Locate Profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Emergency search
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# Initialize Verification Variables
ECFR_VISITS=0
PART141_VISITS=0
BOOKMARK_FOLDER_EXISTS=0
BOOKMARK_COUNT_IN_FOLDER=0
ECFR_BOOKMARKS=0

if [ -f "$PLACES_DB" ]; then
    # Force checkpoint
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check History for ecfr.gov
        ECFR_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%ecfr.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check History specifically for Part 141 pages
        PART141_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%ecfr.gov%' AND p.url LIKE '%141%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        # Check Bookmark Folder "EPA Compliance"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title)='epa compliance' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            BOOKMARK_FOLDER_EXISTS=1
            
            # Count bookmarks in that folder
            BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE type=1 AND parent=${FOLDER_ID};" 2>/dev/null || echo "0")
            
            # Count bookmarks in that folder that are specifically ecfr.gov
            ECFR_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id
                 WHERE b.type=1 AND b.parent=${FOLDER_ID} AND p.url LIKE '%ecfr.gov%';" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# Check Output JSON
OUTPUT_FILE="/home/ga/Documents/water_mcl_limits.json"
FILE_EXISTS=0
FILE_FRESH=0
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "ecfr_visits": $ECFR_VISITS,
    "part141_visits": $PART141_VISITS,
    "bookmark_folder_exists": $BOOKMARK_FOLDER_EXISTS,
    "bookmarks_in_folder": $BOOKMARK_COUNT_IN_FOLDER,
    "ecfr_bookmarks": $ECFR_BOOKMARKS,
    "file_exists": $FILE_EXISTS,
    "file_fresh": $FILE_FRESH,
    "file_size": $FILE_SIZE
}
EOF

# Copy file content to temp location for verifier to read safely
if [ "$FILE_EXISTS" -eq 1 ]; then
    cp "$OUTPUT_FILE" /tmp/water_mcl_limits_content.json 2>/dev/null || true
    chmod 644 /tmp/water_mcl_limits_content.json 2>/dev/null || true
fi

# Move result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="