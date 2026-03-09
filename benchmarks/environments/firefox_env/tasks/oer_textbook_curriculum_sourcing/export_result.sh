#!/bin/bash
# export_result.sh - Post-task hook for oer_textbook_curriculum_sourcing

echo "=== Exporting OER Sourcing Results ==="

# Capture final visual state
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Kill Firefox to flush database WAL to disk
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Load task start timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# Locate Firefox profile
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search if tmp file missing
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
fi
PLACES_DB="$PROFILE_DIR/places.sqlite"

# --- Analyze Browser Data (Bookmarks & History) ---
FOLDER_FOUND="false"
BOOKMARK_COUNT=0
HISTORY_VISITS=0
OPENSTAX_BOOKMARKS=0

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB"
    
    if [ -f "$TEMP_DB" ]; then
        # Check history for openstax.org visits after task start
        HISTORY_VISITS=$(sqlite3 "$TEMP_DB" \
            "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
             WHERE p.url LIKE '%openstax.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
             
        # Check for specific bookmark folder "Fall Curriculum OER"
        FOLDER_ID=$(sqlite3 "$TEMP_DB" \
            "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Fall Curriculum OER' LIMIT 1;" 2>/dev/null || echo "")
            
        if [ -n "$FOLDER_ID" ]; then
            FOLDER_FOUND="true"
            # Count bookmarks within this folder
            BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks WHERE parent=$FOLDER_ID AND type=1;" 2>/dev/null || echo "0")
                
            # Check if bookmarks are actually OpenStax URLs
            OPENSTAX_BOOKMARKS=$(sqlite3 "$TEMP_DB" \
                "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id \
                 WHERE b.parent=$FOLDER_ID AND p.url LIKE '%openstax.org%' AND b.type=1;" 2>/dev/null || echo "0")
        fi
        
        rm -f "$TEMP_DB"
    fi
fi

# --- Analyze Downloaded PDF ---
PDF_FOUND="false"
PDF_SIZE=0
PDF_FILENAME=""

# Look for large PDF files created after task start in Downloads
# OpenStax textbooks are typically >10MB
# Find largest PDF matching time criteria
LARGEST_PDF=$(find /home/ga/Downloads -name "*.pdf" -newermt "@$TASK_START" -printf "%s %p\n" 2>/dev/null | sort -nr | head -1)

if [ -n "$LARGEST_PDF" ]; then
    PDF_SIZE=$(echo "$LARGEST_PDF" | awk '{print $1}')
    PDF_PATH=$(echo "$LARGEST_PDF" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
    PDF_FILENAME=$(basename "$PDF_PATH")
    
    # Threshold: 5MB (OpenStax books are usually 30MB+, but let's be safe with 5MB minimum for a full text)
    if [ "$PDF_SIZE" -gt 5242880 ]; then
        PDF_FOUND="true"
    fi
fi

# --- Analyze JSON Report ---
REPORT_FILE="/home/ga/Documents/oer_report.json"
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_FRESH="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Check modification time
    MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
    
    # Check if valid JSON
    if jq . "$REPORT_FILE" >/dev/null 2>&1; then
        REPORT_VALID="true"
    fi
fi

# Compile results into JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START,
  "history_visits_openstax": $HISTORY_VISITS,
  "bookmark_folder_found": $FOLDER_FOUND,
  "bookmark_count_in_folder": $BOOKMARK_COUNT,
  "openstax_bookmarks_count": $OPENSTAX_BOOKMARKS,
  "pdf_download_found": $PDF_FOUND,
  "pdf_filename": "$PDF_FILENAME",
  "pdf_size_bytes": $PDF_SIZE,
  "report_exists": $REPORT_EXISTS,
  "report_fresh": $REPORT_FRESH,
  "report_valid": $REPORT_VALID
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"