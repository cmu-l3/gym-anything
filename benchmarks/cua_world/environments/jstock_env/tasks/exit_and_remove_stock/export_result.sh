#!/bin/bash
echo "=== Exporting exit_and_remove_stock results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_FILE="${JSTOCK_DATA_DIR}/watchlist/My Watchlist/realtimestock.csv"
SELL_FILE="${JSTOCK_DATA_DIR}/portfolios/My Portfolio/sellportfolio.csv"

# 1. Capture Watchlist State
WATCHLIST_EXISTS="false"
WATCHLIST_CONTENT=""
WATCHLIST_MTIME=0
if [ -f "$WATCHLIST_FILE" ]; then
    WATCHLIST_EXISTS="true"
    WATCHLIST_CONTENT=$(cat "$WATCHLIST_FILE" | base64 -w 0)
    WATCHLIST_MTIME=$(stat -c %Y "$WATCHLIST_FILE" 2>/dev/null || echo "0")
fi

# 2. Capture Sell Portfolio State
SELL_FILE_EXISTS="false"
SELL_FILE_CONTENT=""
SELL_FILE_MTIME=0
if [ -f "$SELL_FILE" ]; then
    SELL_FILE_EXISTS="true"
    SELL_FILE_CONTENT=$(cat "$SELL_FILE" | base64 -w 0)
    SELL_FILE_MTIME=$(stat -c %Y "$SELL_FILE" 2>/dev/null || echo "0")
fi

# 3. Check App Status
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "watchlist": {
        "exists": $WATCHLIST_EXISTS,
        "mtime": $WATCHLIST_MTIME,
        "content_b64": "$WATCHLIST_CONTENT"
    },
    "sell_portfolio": {
        "exists": $SELL_FILE_EXISTS,
        "mtime": $SELL_FILE_MTIME,
        "content_b64": "$SELL_FILE_CONTENT"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"