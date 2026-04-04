#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
WATCHLIST_DIR="/home/ga/.jstock/1.0.7/UnitedState/watchlist/Big Banks"
WATCHLIST_CSV="${WATCHLIST_DIR}/realtimestock.csv"
MEMO_PATH="/home/ga/Documents/morning_memo.txt"

# 1. Check if Watchlist Directory Exists
if [ -d "$WATCHLIST_DIR" ]; then
    WATCHLIST_DIR_EXISTS="true"
else
    WATCHLIST_DIR_EXISTS="false"
fi

# 2. Check and Read CSV Content
CSV_CONTENT=""
FILE_CREATED_DURING_TASK="false"
CSV_EXISTS="false"

if [ -f "$WATCHLIST_CSV" ]; then
    CSV_EXISTS="true"
    # Read content (base64 encode to safely pass to JSON)
    CSV_CONTENT=$(cat "$WATCHLIST_CSV" | base64 -w 0)
    
    # Check timestamp
    OUTPUT_MTIME=$(stat -c %Y "$WATCHLIST_CSV" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if Memo was accessed (Access Time)
# This is a heuristic; might not work if noatime is set, but good signal if available
MEMO_ACCESSED="false"
MEMO_ATIME=$(stat -c %X "$MEMO_PATH" 2>/dev/null || echo "0")
if [ "$MEMO_ATIME" -gt "$TASK_START" ]; then
    MEMO_ACCESSED="true"
fi

# 4. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "watchlist_dir_exists": $WATCHLIST_DIR_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_content_base64": "$CSV_CONTENT",
    "memo_accessed": $MEMO_ACCESSED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="