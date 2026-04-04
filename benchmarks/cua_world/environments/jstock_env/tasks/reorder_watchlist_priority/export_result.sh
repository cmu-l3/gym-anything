#!/bin/bash
echo "=== Exporting reorder_watchlist_priority results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")

WATCHLIST_PATH="/home/ga/.jstock/1.0.7/UnitedState/watchlist/My Watchlist/realtimestock.csv"

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$WATCHLIST_PATH" ]; then
    CURRENT_MTIME=$(stat -c %Y "$WATCHLIST_PATH" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if app is running
APP_RUNNING="false"
if pgrep -f "jstock.jar" > /dev/null; then
    APP_RUNNING="true"
    
    # Force JStock to save by sending a graceful close signal (Alt+F4) or just saving
    # Note: JStock usually saves on exit or change. We'll rely on what's on disk.
    # If the file hasn't updated, the agent might need to trigger a save or close the app.
    # We won't force close here to avoid disrupting the agent's state if we wanted to verify live,
    # but since we verify files, we rely on the file on disk.
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "watchlist_path": "$WATCHLIST_PATH"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy the watchlist CSV to /tmp for easier extraction by verifier
if [ -f "$WATCHLIST_PATH" ]; then
    cp "$WATCHLIST_PATH" /tmp/final_watchlist.csv
    chmod 666 /tmp/final_watchlist.csv
fi

echo "Result exported to /tmp/task_result.json"
echo "Watchlist copied to /tmp/final_watchlist.csv"
echo "=== Export complete ==="