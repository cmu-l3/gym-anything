#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Dispatch Terminal Config Result ==="

# 1. Take final screenshot before doing anything destructive
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gracefully close Chrome to flush all Local State, Preferences, and Bookmarks to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 3. Record task end parameters
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Check modification times of critical Chrome files
MODIFIED_DURING_TASK="false"
PREFS="/home/ga/.config/google-chrome-cdp/Default/Preferences"
LOCAL_STATE="/home/ga/.config/google-chrome-cdp/Local State"

if [ -f "$PREFS" ]; then
    PREFS_MTIME=$(stat -c %Y "$PREFS" 2>/dev/null || echo "0")
    if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

if [ -f "$LOCAL_STATE" ]; then
    STATE_MTIME=$(stat -c %Y "$LOCAL_STATE" 2>/dev/null || echo "0")
    if [ "$STATE_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

# 5. Export metadata info JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="