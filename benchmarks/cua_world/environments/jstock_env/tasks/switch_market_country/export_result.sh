#!/bin/bash
echo "=== Exporting switch_market_country results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# JStock stores data in ~/.jstock/1.0.7/<CountryEnumName>
# For UK, the enum is typically "UnitedKingdom"
UK_DIR="/home/ga/.jstock/1.0.7/UnitedKingdom"
WATCHLIST_FILE="$UK_DIR/watchlist/My Watchlist/realtimestock.csv"

# 1. Check if UK directory exists and when it was created
UK_DIR_EXISTS="false"
UK_DIR_CREATED_DURING_TASK="false"

if [ -d "$UK_DIR" ]; then
    UK_DIR_EXISTS="true"
    # Check creation time (ctime) or modification time
    DIR_MTIME=$(stat -c %Y "$UK_DIR" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -gt "$TASK_START" ]; then
        UK_DIR_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Watchlist Content
WATCHLIST_EXISTS="false"
STOCKS_FOUND=""
HAS_HSBA="false"
HAS_BP="false"

if [ -f "$WATCHLIST_FILE" ]; then
    WATCHLIST_EXISTS="true"
    
    # Read the file content
    CONTENT=$(cat "$WATCHLIST_FILE")
    
    # Check for HSBA/HSBC
    if echo "$CONTENT" | grep -q "HSBA"; then
        HAS_HSBA="true"
    fi
    # Check for BP
    if echo "$CONTENT" | grep -q "\"BP\""; then
        HAS_BP="true"
    fi
    
    # Extract codes for debugging/feedback
    # CSV format: "Code","Symbol",...
    # We grab the first column, remove quotes
    STOCKS_FOUND=$(cut -d',' -f1 "$WATCHLIST_FILE" | tr -d '"' | grep -v "timestamp" | grep -v "Code" | tr '\n' ', ')
fi

# 3. Check config file to see if country is set to UK
# JStock config usually at ~/.jstock/config/jstock.xml or .properties
# We rely primarily on the directory structure as it's more robust
CONFIG_FILE="/home/ga/.jstock/config/jstock.properties"
CURRENT_COUNTRY=""
if [ -f "$CONFIG_FILE" ]; then
    # Config format is XML or properties depending on version, grep is safest
    CURRENT_COUNTRY=$(grep -i "UnitedKingdom" "$CONFIG_FILE" || echo "")
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "uk_dir_exists": $UK_DIR_EXISTS,
    "uk_dir_created_during_task": $UK_DIR_CREATED_DURING_TASK,
    "watchlist_exists": $WATCHLIST_EXISTS,
    "has_hsba": $HAS_HSBA,
    "has_bp": $HAS_BP,
    "stocks_found": "$STOCKS_FOUND",
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