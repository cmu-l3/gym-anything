#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Broadcast Meteorologist Task Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Chrome was running
CHROME_RUNNING="false"
if pgrep -f "chrome" > /dev/null; then
    CHROME_RUNNING="true"
fi

# Gracefully close Chrome to flush JSONs (Preferences, Bookmarks, Web Data)
echo "Closing Chrome to flush data to disk..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Export Custom Search Engines from SQLite (Web Data)
echo "Exporting Search Engines from Web Data..."
SEARCH_ENGINES_JSON="/tmp/search_engines.json"
echo "[]" > "$SEARCH_ENGINES_JSON"

WEB_DATA="/home/ga/.config/google-chrome/Default/Web Data"
if [ -f "$WEB_DATA" ]; then
    # Query keywords table and export as JSON array of objects
    sqlite3 -json "$WEB_DATA" "SELECT keyword, url FROM keywords;" > "$SEARCH_ENGINES_JSON" 2>/dev/null || echo "[]" > "$SEARCH_ENGINES_JSON"
fi

# Record export data
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create summary JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "chrome_was_running": $CHROME_RUNNING
}
EOF

chmod 666 /tmp/task_result.json
chmod 666 "$SEARCH_ENGINES_JSON"

echo "=== Export Complete ==="