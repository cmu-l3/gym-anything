#!/bin/bash
# Export script for Extension Market Eval task
set -e

TASK_NAME="extension_market_eval"
OUTPUT_FILE="/home/ga/Desktop/extension_comparison.csv"
RESULT_JSON="/tmp/task_result.json"

echo "=== Exporting results for ${TASK_NAME} ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check output file status
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
TASK_START_TS=$(cat "/tmp/task_start_ts_${TASK_NAME}.txt" 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START_TS" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Browser History for Add-ons Store visits
# We look for visits to the search page and detail pages
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
SEARCH_VISITS=0
DETAIL_VISITS=0

if [ -f "$HISTORY_DB" ]; then
    # Copy DB to avoid locks
    cp "$HISTORY_DB" /tmp/history_check.sqlite
    
    # Check for search URL (microsoftedge.microsoft.com/addons/search/...)
    SEARCH_VISITS=$(sqlite3 /tmp/history_check.sqlite "SELECT COUNT(*) FROM urls WHERE url LIKE '%microsoftedge.microsoft.com/addons/search%';" 2>/dev/null || echo "0")
    
    # Check for detail URL (microsoftedge.microsoft.com/addons/detail/...)
    DETAIL_VISITS=$(sqlite3 /tmp/history_check.sqlite "SELECT COUNT(*) FROM urls WHERE url LIKE '%microsoftedge.microsoft.com/addons/detail%';" 2>/dev/null || echo "0")
    
    rm /tmp/history_check.sqlite
fi

# 4. Generate Result JSON
# We don't read the CSV content here; verifier.py will copy the file and parse it safely
cat > "$RESULT_JSON" <<EOF
{
  "task_start_ts": $TASK_START_TS,
  "output_file": {
    "exists": $FILE_EXISTS,
    "size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "path": "$OUTPUT_FILE"
  },
  "history": {
    "search_visits": $SEARCH_VISITS,
    "detail_visits": $DETAIL_VISITS
  }
}
EOF

# Set permissions so host can read
chmod 644 "$RESULT_JSON" 2>/dev/null || true
if [ "$FILE_EXISTS" == "true" ]; then
    chmod 644 "$OUTPUT_FILE" 2>/dev/null || true
fi

echo "Export complete. Result JSON:"
cat "$RESULT_JSON"