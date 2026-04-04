#!/bin/bash
echo "=== Exporting organize_watchlists_by_sector results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState/watchlist"

# 1. Take final screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png" 2>/dev/null || true

# 2. Helper function to extract stocks from a watchlist CSV
extract_stocks() {
    local folder_name="$1"
    local csv_path="${JSTOCK_DATA_DIR}/${folder_name}/realtimestock.csv"
    
    if [ ! -f "$csv_path" ]; then
        echo "[]"
        return
    fi
    
    # Parse CSV: skip header, extract 2nd column (Symbol), remove quotes
    # JStock CSV format: "Code","Symbol",...
    # We use awk to grab the second column, stripping quotes.
    # Note: Handles standard CSV structure
    cat "$csv_path" | awk -F',' 'NR>1 {gsub(/"/, "", $2); print $2}' | grep -v "^$" | sort | uniq | jq -R . | jq -s .
}

# 3. Helper to check file modification time (Anti-gaming)
check_mtime() {
    local folder_name="$1"
    local csv_path="${JSTOCK_DATA_DIR}/${folder_name}/realtimestock.csv"
    
    if [ ! -f "$csv_path" ]; then
        echo "false"
        return
    fi
    
    local mtime=$(stat -c %Y "$csv_path")
    if [ "$mtime" -gt "$TASK_START" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# 4. Extract data for "My Watchlist"
MY_WATCHLIST_STOCKS=$(extract_stocks "My Watchlist")
MY_WATCHLIST_MODIFIED=$(check_mtime "My Watchlist")

# 5. Extract data for "Semiconductors"
# Note: Check strict naming
SEMICON_EXISTS="false"
if [ -d "${JSTOCK_DATA_DIR}/Semiconductors" ]; then
    SEMICON_EXISTS="true"
fi
SEMICON_STOCKS=$(extract_stocks "Semiconductors")
SEMICON_MODIFIED=$(check_mtime "Semiconductors")

# 6. Extract data for "Software & Cloud"
# Note: Handle potential URL encoding or spaces in shell
SOFT_EXISTS="false"
SOFT_STOCKS="[]"
SOFT_MODIFIED="false"

if [ -d "${JSTOCK_DATA_DIR}/Software & Cloud" ]; then
    SOFT_EXISTS="true"
    SOFT_STOCKS=$(extract_stocks "Software & Cloud")
    SOFT_MODIFIED=$(check_mtime "Software & Cloud")
elif [ -d "${JSTOCK_DATA_DIR}/Software %26 Cloud" ]; then
    # Fallback if JStock encodes the name differently
    SOFT_EXISTS="true"
    SOFT_STOCKS=$(extract_stocks "Software %26 Cloud")
    SOFT_MODIFIED=$(check_mtime "Software %26 Cloud")
fi

# 7. Check if JStock is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 8. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "export_time": $EXPORT_TIME,
    "app_running": $APP_RUNNING,
    "watchlists": {
        "My Watchlist": {
            "exists": true,
            "stocks": $MY_WATCHLIST_STOCKS,
            "modified_during_task": $MY_WATCHLIST_MODIFIED
        },
        "Semiconductors": {
            "exists": $SEMICON_EXISTS,
            "stocks": $SEMICON_STOCKS,
            "modified_during_task": $SEMICON_MODIFIED
        },
        "Software & Cloud": {
            "exists": $SOFT_EXISTS,
            "stocks": $SOFT_STOCKS,
            "modified_during_task": $SOFT_MODIFIED
        }
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 9. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="