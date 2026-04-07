#!/bin/bash
echo "=== Exporting archive_mongodb_old_posts result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check MongoDB Remaining counts
MONGO_SHELL="mongosh"
if ! command -v mongosh >/dev/null 2>&1; then
    MONGO_SHELL="mongo"
fi

# Extract strictly the numeric output
OLD_REMAINING=$($MONGO_SHELL --quiet socioboard --eval 'db.published_posts.countDocuments({published_date: {$lt: new Date("2023-01-01T00:00:00Z")}}) ' 2>/dev/null | tail -n 1 || echo "0")
RECENT_REMAINING=$($MONGO_SHELL --quiet socioboard --eval 'db.published_posts.countDocuments({published_date: {$gte: new Date("2023-01-01T00:00:00Z")}}) ' 2>/dev/null | tail -n 1 || echo "0")

OLD_REMAINING=$(echo "$OLD_REMAINING" | grep -oE '^[0-9]+$' || echo "0")
RECENT_REMAINING=$(echo "$RECENT_REMAINING" | grep -oE '^[0-9]+$' || echo "0")

# Check archive
ARCHIVE_PATH="/home/ga/Archives/posts_pre_2023.json.gz"
ARCHIVE_EXISTS="false"
ARCHIVE_SIZE="0"
ARCHIVE_LINES="0"
IS_GZIP="false"

if [ -f "$ARCHIVE_PATH" ]; then
    ARCHIVE_EXISTS="true"
    ARCHIVE_SIZE=$(stat -c %s "$ARCHIVE_PATH" 2>/dev/null || echo "0")
    if file "$ARCHIVE_PATH" | grep -qi "gzip"; then
        IS_GZIP="true"
        
        # Use jq to count documents robustly, handling both standard JSON-lines and --jsonArray exports
        JQ_COUNT=$(gzip -dc "$ARCHIVE_PATH" 2>/dev/null | jq 'if type=="array" then length else 1 end' 2>/dev/null | awk '{s+=$1} END {print s}')
        
        if [ -n "$JQ_COUNT" ] && [ "$JQ_COUNT" != "0" ] && [ "$JQ_COUNT" != "" ]; then
            ARCHIVE_LINES=$JQ_COUNT
        else
            # Fallback to line counting if jq fails
            ARCHIVE_LINES=$(gzip -dc "$ARCHIVE_PATH" 2>/dev/null | wc -l || echo "0")
        fi
    fi
fi

if [ -z "$ARCHIVE_LINES" ]; then
    ARCHIVE_LINES="0"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "old_remaining": $OLD_REMAINING,
    "recent_remaining": $RECENT_REMAINING,
    "archive_exists": $ARCHIVE_EXISTS,
    "archive_size": $ARCHIVE_SIZE,
    "archive_lines": $ARCHIVE_LINES,
    "is_gzip": $IS_GZIP
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="