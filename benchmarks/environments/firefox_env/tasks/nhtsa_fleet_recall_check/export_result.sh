#!/bin/bash
# export_result.sh - Post-task hook for nhtsa_fleet_recall_check

set -e
echo "=== Exporting NHTSA Fleet Recall Check results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 3. Force Firefox to close to flush WAL (Write-Ahead Log) to places.sqlite
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 4. Locate places.sqlite
PROFILE_DIR=$(cat /tmp/firefox_profile_path.txt 2>/dev/null)
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/places.sqlite" ]; then
    # Fallback search
    PROFILE_DIR=$(find /home/ga -name places.sqlite 2>/dev/null | head -n 1 | xargs dirname)
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"
echo "Using database: $PLACES_DB"

# 5. Extract Browser Data (History & Bookmarks)
# We copy the DB to temp to avoid locks and permission issues
TEMP_DB="/tmp/places_export.sqlite"
cp "$PLACES_DB" "$TEMP_DB"

# Query 1: History count for nhtsa.gov since task start
NHTSA_VISITS=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id WHERE p.url LIKE '%nhtsa.gov%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")

# Query 2: Check for 'Fleet Safety Recalls' bookmark folder
FOLDER_ID=$(sqlite3 "$TEMP_DB" "SELECT id FROM moz_bookmarks WHERE type=2 AND title='Fleet Safety Recalls';" 2>/dev/null || echo "")

FOLDER_EXISTS="false"
BOOKMARK_COUNT=0

if [ -n "$FOLDER_ID" ]; then
    FOLDER_EXISTS="true"
    # Query 3: Count bookmarks within that folder that point to nhtsa.gov
    BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks b JOIN moz_places p ON b.fk=p.id WHERE b.parent=$FOLDER_ID AND b.type=1 AND p.url LIKE '%nhtsa.gov%';" 2>/dev/null || echo "0")
fi

rm -f "$TEMP_DB"

# 6. Check Report File Metadata (Verifier will check content)
REPORT_FILE="/home/ga/Documents/fleet_recall_report.json"
REPORT_EXISTS="false"
REPORT_FRESH="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    fi
fi

# 7. Create result JSON for the verifier
# We bundle the system-level checks here. The verifier will read this AND the agent's report.
cat > /tmp/task_result.json << EOF
{
  "task_start_timestamp": $TASK_START,
  "nhtsa_visits": $NHTSA_VISITS,
  "bookmark_folder_exists": $FOLDER_EXISTS,
  "nhtsa_bookmarks_count": $BOOKMARK_COUNT,
  "report_file_exists": $REPORT_EXISTS,
  "report_file_fresh": $REPORT_FRESH,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions so verifier (running as root/user) can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json