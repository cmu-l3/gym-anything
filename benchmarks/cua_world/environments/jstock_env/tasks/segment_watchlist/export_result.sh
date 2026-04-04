#!/bin/bash
echo "=== Exporting segment_watchlist results ==="

# Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"
DEFAULT_WATCHLIST_FILE="${WATCHLIST_BASE}/My Watchlist/realtimestock.csv"
TARGET_WATCHLIST_FILE="${WATCHLIST_BASE}/Core Holdings/realtimestock.csv"
TARGET_WATCHLIST_DIR="${WATCHLIST_BASE}/Core Holdings"

# Time verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Target Watchlist ("Core Holdings")
TARGET_EXISTS=false
TARGET_CREATED_DURING_TASK=false
TARGET_CONTENT=""

if [ -f "$TARGET_WATCHLIST_FILE" ]; then
    TARGET_EXISTS=true
    TARGET_MTIME=$(stat -c %Y "$TARGET_WATCHLIST_FILE" 2>/dev/null || echo "0")
    
    # Check directory creation time as well
    DIR_CTIME=$(stat -c %Y "$TARGET_WATCHLIST_DIR" 2>/dev/null || echo "0")
    
    if [ "$DIR_CTIME" -gt "$TASK_START" ] || [ "$TARGET_MTIME" -gt "$TASK_START" ]; then
        TARGET_CREATED_DURING_TASK=true
    fi
    
    # Read content (escape quotes for JSON)
    TARGET_CONTENT=$(cat "$TARGET_WATCHLIST_FILE" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
fi

# 2. Check Source Watchlist ("My Watchlist")
SOURCE_EXISTS=false
SOURCE_MODIFIED_DURING_TASK=false
SOURCE_CONTENT=""

if [ -f "$DEFAULT_WATCHLIST_FILE" ]; then
    SOURCE_EXISTS=true
    SOURCE_MTIME=$(stat -c %Y "$DEFAULT_WATCHLIST_FILE" 2>/dev/null || echo "0")
    
    if [ "$SOURCE_MTIME" -gt "$TASK_START" ]; then
        SOURCE_MODIFIED_DURING_TASK=true
    fi
    
    SOURCE_CONTENT=$(cat "$DEFAULT_WATCHLIST_FILE" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
fi

# 3. Check if JStock is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "target_watchlist": {
        "exists": $TARGET_EXISTS,
        "created_during_task": $TARGET_CREATED_DURING_TASK,
        "content": "$TARGET_CONTENT",
        "path": "$TARGET_WATCHLIST_FILE"
    },
    "source_watchlist": {
        "exists": $SOURCE_EXISTS,
        "modified_during_task": $SOURCE_MODIFIED_DURING_TASK,
        "content": "$SOURCE_CONTENT",
        "path": "$DEFAULT_WATCHLIST_FILE"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="