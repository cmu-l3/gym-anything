#!/bin/bash
echo "=== Exporting remove_stocks_from_watchlist result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WATCHLIST_CSV="/home/ga/.jstock/1.0.7/UnitedState/watchlist/My Watchlist/realtimestock.csv"

# Take final screenshot BEFORE closing app (shows UI state)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png" 2>/dev/null || true

# ============================================================
# Force Save / Graceful Close
# JStock might keep changes in memory until saved or closed
# ============================================================
echo "Forcing save and close..."
if pgrep -f "jstock.jar" > /dev/null 2>&1; then
    # Focus window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true
    sleep 1
    
    # Send Ctrl+S (Save)
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key ctrl+s" 2>/dev/null || true
    sleep 2
    
    # Close window gracefully (Alt+F4) to ensure file write
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4" 2>/dev/null || true
    sleep 3
    
    # Confirm "Do you want to exit?" dialog if it appears (Enter)
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
    sleep 5
fi

# Kill if still running
pkill -f "jstock.jar" 2>/dev/null || true
sleep 1

# ============================================================
# Analyze Result File
# ============================================================
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_CHANGED_CONTENT="false"
STOCK_LIST="[]"
ROW_COUNT=0

if [ -f "$WATCHLIST_CSV" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$WATCHLIST_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check if content changed from initial state (anti-gaming)
    if [ -f /tmp/initial_watchlist.csv ]; then
        if diff -q "$WATCHLIST_CSV" /tmp/initial_watchlist.csv > /dev/null 2>&1; then
            FILE_CHANGED_CONTENT="false"
        else
            FILE_CHANGED_CONTENT="true"
        fi
    fi
    
    # Extract stock codes using grep/sed/awk to JSON array
    # Matches lines like: "AAPL","AAPL",...
    # Extracts the first column (Code)
    STOCKS=$(grep -oE '^"[A-Z]+"' "$WATCHLIST_CSV" | sed 's/"//g' | tr '\n' ',' | sed 's/,$//')
    
    # Convert to JSON array string
    if [ -n "$STOCKS" ]; then
        STOCK_LIST="[\"$(echo "$STOCKS" | sed 's/,/","/g')\"]"
    fi
    
    # Count data rows (excluding timestamp header and column header)
    # Header row starts with "Code"
    # Data rows start with "LETTER"
    ROW_COUNT=$(grep -cE '^"[A-Z]+"' "$WATCHLIST_CSV" || echo "0")
fi

# ============================================================
# Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_content_changed": $FILE_CHANGED_CONTENT,
    "stock_list": $STOCK_LIST,
    "row_count": $ROW_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="