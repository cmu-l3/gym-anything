#!/bin/bash
# export_result.sh - Post-task hook for clinical_trials_competitor_monitoring
set -e

echo "=== Exporting Clinical Trials Task Result ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Firefox to flush SQLite WAL (Write-Ahead Log)
# This ensures all history/bookmarks are committed to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Environment/State
TASK_START=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")
# Convert to microseconds for Firefox history comparison
TASK_START_US=$((TASK_START * 1000000))
PROFILE_DIR=$(cat /tmp/firefox_profile_path.txt 2>/dev/null || echo "")

# Fallback profile search if temp file is missing/empty
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"
OUTPUT_FILE="/home/ga/Documents/trial_intelligence.json"

# 4. Check Output File Stats
FILE_EXISTS="false"
FILE_FRESH="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    fi
fi

# 5. Query Firefox Database (History & Bookmarks)
HISTORY_VISITS_CT=0
HISTORY_HAS_FILTERS="false"
BOOKMARK_FOLDER_FOUND="false"
BOOKMARK_COUNT_IN_FOLDER=0

if [ -f "$PLACES_DB" ]; then
    # Copy DB to temp to avoid locks
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    # Check History: Visits to clinicaltrials.gov
    HISTORY_VISITS_CT=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%clinicaltrials.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

    # Check History: Usage of search filters
    # Look for URLs containing filter parameters. 
    # ClinicalTrials.gov uses various params like 'cond', 'aggFilters', 'status', 'intr'.
    # We check for the condition 'Glioblastoma' appearing in the URL
    FILTER_CHECK=$(sqlite3 "$TEMP_DB" \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id 
         WHERE p.url LIKE '%clinicaltrials.gov%' 
         AND (p.url LIKE '%Glioblastoma%' OR p.url LIKE '%glioblastoma%')
         AND (p.url LIKE '%Recruiting%' OR p.url LIKE '%recruiting%' OR p.url LIKE '%status%' OR p.url LIKE '%aggFilters%')
         AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
    
    if [ "$FILTER_CHECK" -gt "0" ]; then
        HISTORY_HAS_FILTERS="true"
    fi

    # Check Bookmarks: Folder "Glioblastoma Phase 3"
    FOLDER_ID=$(sqlite3 "$TEMP_DB" \
        "SELECT id FROM moz_bookmarks WHERE type=2 AND title LIKE 'Glioblastoma Phase 3' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$FOLDER_ID" ]; then
        BOOKMARK_FOLDER_FOUND="true"
        # Count bookmarks inside this folder
        BOOKMARK_COUNT_IN_FOLDER=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
    fi

    rm -f "$TEMP_DB"
fi

# 6. Prepare Result JSON
TEMP_JSON="/tmp/task_result.json"

cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "file_exists": $FILE_EXISTS,
  "file_fresh": $FILE_FRESH,
  "file_size": $FILE_SIZE,
  "history_visits_ct": $HISTORY_VISITS_CT,
  "history_has_filters": $HISTORY_HAS_FILTERS,
  "bookmark_folder_found": $BOOKMARK_FOLDER_FOUND,
  "bookmark_count_in_folder": $BOOKMARK_COUNT_IN_FOLDER,
  "output_file_path": "$OUTPUT_FILE"
}
EOF

# 7. Make Output File Available to Verifier (if it exists)
# We copy it to /tmp so copy_from_env can grab it easily without permission issues
if [ "$FILE_EXISTS" == "true" ]; then
    cp "$OUTPUT_FILE" /tmp/trial_intelligence.json
    chmod 644 /tmp/trial_intelligence.json
fi

chmod 644 "$TEMP_JSON"
echo "Export complete. Result saved to $TEMP_JSON"