#!/bin/bash
# Export results for USDA Nutritional Analysis task

set -e
echo "=== Exporting USDA Nutritional Analysis Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/nutrition_report.txt"

# 1. Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    # Read content, limit size to avoid issues
    REPORT_CONTENT=$(head -c 4096 "$REPORT_PATH")
fi

# 3. Check Downloads
# Look for any file in Downloads created after task start
DOWNLOAD_FOUND="false"
DOWNLOAD_FILENAME=""

# Find files in Downloads, sort by time
# We look for files modified after TASK_START
FOUND_FILES=$(find /home/ga/Downloads -type f -newermt "@$TASK_START")

if [ -n "$FOUND_FILES" ]; then
    DOWNLOAD_FOUND="true"
    # Just take the first one found as evidence
    DOWNLOAD_FILENAME=$(echo "$FOUND_FILES" | head -n 1)
fi

# 4. Check Browser History for USDA visits
# We need to query the SQLite DB. Copy it first to avoid locks.
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
TEMP_DB="/tmp/history_copy.sqlite"
USDA_VISITED="false"

if [ -f "$HISTORY_DB" ]; then
    cp "$HISTORY_DB" "$TEMP_DB"
    # Query for visits to fdc.nal.usda.gov
    # We look for hits that happened recently (approximate check by existence in recent history)
    # Note: timestamps in Chrome history are microseconds since 1601. Complex to converting bash.
    # We'll just check if the URL exists in the table at all, simpler for this environment context 
    # assuming clean profile or we accept any visit as partial evidence.
    # Ideally, we check visit_time, but for this script, existence is a strong enough signal combined with task start.
    
    VISIT_COUNT=$(sqlite3 "$TEMP_DB" "SELECT count(*) FROM urls WHERE url LIKE '%fdc.nal.usda.gov%';" 2>/dev/null || echo "0")
    
    if [ "$VISIT_COUNT" -gt "0" ]; then
        USDA_VISITED="true"
    fi
    rm -f "$TEMP_DB"
fi

# 5. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R -s '.'),
    "download_found": $DOWNLOAD_FOUND,
    "download_filename": "$DOWNLOAD_FILENAME",
    "usda_visited": $USDA_VISITED
}
EOF

# Set permissions so verifier can read it (if running as different user)
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"