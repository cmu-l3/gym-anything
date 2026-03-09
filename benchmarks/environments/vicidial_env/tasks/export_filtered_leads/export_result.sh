#!/bin/bash
echo "=== Exporting task results ==="

# Source utils
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Find the exported file
# We look for the most recently modified file in ~/Downloads that is a text/csv file
DOWNLOAD_DIR="/home/ga/Downloads"
EXPORT_FILE=$(find "$DOWNLOAD_DIR" -type f \( -name "*.txt" -o -name "*.csv" \) -newermt "@$TASK_START" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

FILE_EXISTS="false"
FILE_PATH=""
FILE_CONTENT=""
ROW_COUNT=0
FL_COUNT=0
WRONG_STATE_COUNT=0
WRONG_LIST_COUNT=0

if [ -n "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_PATH="$EXPORT_FILE"
    echo "Found export file: $FILE_PATH"
    
    # Read content for verification (limit size just in case)
    FILE_CONTENT=$(head -n 20 "$FILE_PATH" | base64 -w 0)
    
    # Analyze content using simple grep/awk tools to pass stats to python verifier
    # Vicidial exports usually are tab-delimited or pipe-delimited or CSV.
    # We will let the python verifier do the heavy lifting of parsing, 
    # but we'll capture the raw content.
    
    # Simple check for FL and 9001 in the file
    FL_COUNT=$(grep -c "FL" "$FILE_PATH" || echo 0)
    # Check for list_id 9001
    LIST_COUNT=$(grep -c "9001" "$FILE_PATH" || echo 0)
else
    echo "No new export file found in $DOWNLOAD_DIR"
fi

# 2. Check Database Logs for 'SEARCH' or 'EXPORT' activity by user 6666
# Vicidial logs admin activity in vicidial_admin_log
ADMIN_LOG_ACTIVITY="false"
LOG_QUERY="SELECT count(*) FROM vicidial_admin_log WHERE user='6666' AND event_date > FROM_UNIXTIME($TASK_START) AND (action LIKE '%SEARCH%' OR action LIKE '%EXPORT%' OR action LIKE '%DOWNLOAD%');"
LOG_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$LOG_QUERY" 2>/dev/null || echo "0")

if [ "$LOG_COUNT" -gt "0" ]; then
    ADMIN_LOG_ACTIVITY="true"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$FILE_PATH",
    "file_content_base64": "$FILE_CONTENT",
    "admin_log_activity": $ADMIN_LOG_ACTIVITY,
    "admin_log_count": $LOG_COUNT,
    "simple_fl_match_count": $FL_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="