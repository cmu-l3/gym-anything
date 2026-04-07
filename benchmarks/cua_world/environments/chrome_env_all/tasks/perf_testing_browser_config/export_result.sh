#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 1. Gracefully close Chrome to flush Preferences and Local State to disk
echo "Flushing Chrome data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true

# 2. Extract Custom Search Engines from SQLite databases
# Chrome stores user-added search engines in 'Web Data' DB, not just Preferences.
echo "Extracting search engines from Web Data..."
touch /tmp/search_engines_export.txt
chmod 666 /tmp/search_engines_export.txt

# Check standard profile
if [ -f "/home/ga/.config/google-chrome/Default/Web Data" ]; then
    sqlite3 "/home/ga/.config/google-chrome/Default/Web Data" "SELECT keyword, url FROM keywords;" >> /tmp/search_engines_export.txt 2>/dev/null || true
fi

# Check CDP profile
if [ -f "/home/ga/.config/google-chrome-cdp/Default/Web Data" ]; then
    sqlite3 "/home/ga/.config/google-chrome-cdp/Default/Web Data" "SELECT keyword, url FROM keywords;" >> /tmp/search_engines_export.txt 2>/dev/null || true
fi

# 3. Get modification times of Chrome configuration files
# Used to verify the agent actually made changes during the task timeframe
PREFS_MTIME=0
if [ -f "/home/ga/.config/google-chrome-cdp/Default/Preferences" ]; then
    PREFS_MTIME=$(stat -c %Y "/home/ga/.config/google-chrome-cdp/Default/Preferences" 2>/dev/null || echo "0")
elif [ -f "/home/ga/.config/google-chrome/Default/Preferences" ]; then
    PREFS_MTIME=$(stat -c %Y "/home/ga/.config/google-chrome/Default/Preferences" 2>/dev/null || echo "0")
fi

STATE_MTIME=0
if [ -f "/home/ga/.config/google-chrome-cdp/Local State" ]; then
    STATE_MTIME=$(stat -c %Y "/home/ga/.config/google-chrome-cdp/Local State" 2>/dev/null || echo "0")
elif [ -f "/home/ga/.config/google-chrome/Local State" ]; then
    STATE_MTIME=$(stat -c %Y "/home/ga/.config/google-chrome/Local State" 2>/dev/null || echo "0")
fi

# 4. Create JSON export summary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_mtime": $PREFS_MTIME,
    "state_mtime": $STATE_MTIME,
    "screenshot_path": "/tmp/task_final.png",
    "search_engines_exported": $([ -s /tmp/search_engines_export.txt ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="