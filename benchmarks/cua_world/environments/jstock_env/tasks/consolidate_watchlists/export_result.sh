#!/bin/bash
echo "=== Exporting consolidate_watchlists result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"
TECH_CSV="${WATCHLIST_BASE}/Tech/realtimestock.csv"
AUTO_DIR="${WATCHLIST_BASE}/Auto"

# 1. Analyze 'Tech' Watchlist (Destination)
TECH_EXISTS="false"
TECH_MODIFIED="false"
TECH_STOCKS="[]"

if [ -f "$TECH_CSV" ]; then
    TECH_EXISTS="true"
    
    # Check modification time
    TECH_MTIME=$(stat -c %Y "$TECH_CSV" 2>/dev/null || echo "0")
    if [ "$TECH_MTIME" -gt "$TASK_START" ]; then
        TECH_MODIFIED="true"
    fi
    
    # Extract stock codes (column 1), skip header lines
    # CSV format: "Code","Symbol",...
    # We want to extract the first column, strip quotes
    TECH_STOCKS=$(grep -v "timestamp=" "$TECH_CSV" | grep -v "\"Code\"" | cut -d',' -f1 | sed 's/"//g' | jq -R . | jq -s .)
else
    TECH_STOCKS="[]"
fi

# 2. Analyze 'Auto' Watchlist (Source - should be deleted)
AUTO_EXISTS="false"
if [ -d "$AUTO_DIR" ]; then
    AUTO_EXISTS="true"
fi

# 3. Check if App is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tech_watchlist_exists": $TECH_EXISTS,
    "tech_watchlist_modified": $TECH_MODIFIED,
    "tech_stocks": $TECH_STOCKS,
    "auto_watchlist_exists": $AUTO_EXISTS,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="