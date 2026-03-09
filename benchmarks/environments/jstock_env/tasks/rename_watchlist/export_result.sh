#!/bin/bash
echo "=== Exporting rename_watchlist result ==="

# Define paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"
OLD_WATCHLIST="${WATCHLIST_BASE}/My Watchlist"
NEW_WATCHLIST="${WATCHLIST_BASE}/Tech Giants"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if NEW directory exists
if [ -d "$NEW_WATCHLIST" ]; then
    NEW_DIR_EXISTS="true"
    # Check modification time of the directory
    DIR_MTIME=$(stat -c %Y "$NEW_WATCHLIST" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
else
    NEW_DIR_EXISTS="false"
    MODIFIED_DURING_TASK="false"
fi

# 2. Check if OLD directory is gone (renamed)
if [ -d "$OLD_WATCHLIST" ]; then
    OLD_DIR_GONE="false"
else
    OLD_DIR_GONE="true"
fi

# 3. Check content preservation (Do all 5 stocks exist in the new location?)
STOCKS_PRESERVED="false"
STOCK_COUNT=0
if [ "$NEW_DIR_EXISTS" = "true" ] && [ -f "$NEW_WATCHLIST/realtimestock.csv" ]; then
    # Count occurrences of expected tickers
    # We look for "AAPL", "MSFT", etc. in the file
    STOCKS_FOUND=0
    for stock in "AAPL" "MSFT" "GOOGL" "AMZN" "NVDA"; do
        if grep -q "\"$stock\"" "$NEW_WATCHLIST/realtimestock.csv"; then
            STOCKS_FOUND=$((STOCKS_FOUND + 1))
        fi
    done
    STOCK_COUNT=$STOCKS_FOUND
    if [ "$STOCKS_FOUND" -eq 5 ]; then
        STOCKS_PRESERVED="true"
    fi
fi

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 5. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "new_dir_exists": $NEW_DIR_EXISTS,
    "old_dir_gone": $OLD_DIR_GONE,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "stocks_preserved": $STOCKS_PRESERVED,
    "stock_count": $STOCK_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="