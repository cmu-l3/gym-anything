#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Prepress Terminal Task Results ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Gracefully close Chrome to flush Preferences, Local State, and Web Data (SQLite) to disk
echo "Closing Chrome to flush data..."
pkill -15 -f "google-chrome" 2>/dev/null || true
sleep 4
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 4. Copy required state files to /tmp for verifier access
CHROME_DIR="/home/ga/.config/google-chrome"
CHROME_PROFILE="$CHROME_DIR/Default"

cp "$CHROME_PROFILE/Preferences" /tmp/Preferences.json 2>/dev/null || echo "{}" > /tmp/Preferences.json
cp "$CHROME_DIR/Local State" /tmp/Local_State.json 2>/dev/null || echo "{}" > /tmp/Local_State.json
cp "$CHROME_PROFILE/Bookmarks" /tmp/Bookmarks.json 2>/dev/null || echo "{}" > /tmp/Bookmarks.json
cp "$CHROME_PROFILE/Web Data" /tmp/Web_Data.sqlite 2>/dev/null || true

# 5. Extract Modification Times (Anti-Gaming)
PREFS_MTIME=$(stat -c %Y "$CHROME_PROFILE/Preferences" 2>/dev/null || echo 0)
LOCAL_STATE_MTIME=$(stat -c %Y "$CHROME_DIR/Local State" 2>/dev/null || echo 0)
BKS_MTIME=$(stat -c %Y "$CHROME_PROFILE/Bookmarks" 2>/dev/null || echo 0)
WEBDATA_MTIME=$(stat -c %Y "$CHROME_PROFILE/Web Data" 2>/dev/null || echo 0)

# Check if app was running
APP_RUNNING="true" # We killed it, but if we made it here cleanly, it was likely running.

# 6. Create JSON summary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_mtime": $PREFS_MTIME,
    "local_state_mtime": $LOCAL_STATE_MTIME,
    "bks_mtime": $BKS_MTIME,
    "webdata_mtime": $WEBDATA_MTIME,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/Preferences.json /tmp/Local_State.json /tmp/Bookmarks.json /tmp/Web_Data.sqlite 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="