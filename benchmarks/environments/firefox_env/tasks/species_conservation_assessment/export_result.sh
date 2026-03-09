#!/bin/bash
# export_result.sh - Post-task hook for species_conservation_assessment

echo "=== Exporting species_conservation_assessment results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush WAL to disk
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Locate Firefox profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search if tmp file missing
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

# --- Database Extraction ---
IUCN_VISITS=0
ECOS_VISITS=0
NATURESERVE_VISITS=0
FOLDER_EXISTS=0
FOLDER_BOOKMARK_COUNT=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint to ensure data is in main DB file
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null
    
    if [ -f "$TEMP_DB" ]; then
        # Check history visits to required domains
        IUCN_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%iucnredlist.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        ECOS_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%ecos.fws.gov%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")
             
        NATURESERVE_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(DISTINCT p.id) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id
             WHERE p.url LIKE '%natureserve.org%' AND h.visit_date > ${TASK_START_US};" 2>/dev/null || echo "0")

        # Check for "Conservation Assessment" bookmark folder
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND lower(title) LIKE '%conservation assessment%' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_EXISTS=1
            # Count bookmarks within this folder
            FOLDER_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=${FOLDER_ID} AND type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# --- File Analysis ---
OUTPUT_FILE="/home/ga/Documents/species_assessment.json"
FILE_EXISTS=0
FILE_FRESH=0
JSON_CONTENT="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=1
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH=1
    fi
    # Read content safely
    JSON_CONTENT=$(cat "$OUTPUT_FILE")
fi

# Construct export JSON
EXPORT_JSON="/tmp/task_result.json"
cat > "$EXPORT_JSON" <<EOF
{
  "task_start": $TASK_START,
  "history": {
    "iucn_visits": $IUCN_VISITS,
    "ecos_visits": $ECOS_VISITS,
    "natureserve_visits": $NATURESERVE_VISITS
  },
  "bookmarks": {
    "folder_exists": $FOLDER_EXISTS,
    "count": $FOLDER_BOOKMARK_COUNT
  },
  "file": {
    "exists": $FILE_EXISTS,
    "fresh": $FILE_FRESH,
    "content": $JSON_CONTENT
  }
}
EOF

# Ensure permissions
chmod 666 "$EXPORT_JSON"

echo "Export complete. Result saved to $EXPORT_JSON"