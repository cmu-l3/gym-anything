#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Customs Broker Workspace Task Result ==="

# Record export start time
TASK_END=$(date +%s)
echo "$TASK_END" > /tmp/task_end_time.txt

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We must gracefully close Chrome so it writes in-memory settings (Preferences, Bookmarks) to disk
echo "Flushing Chrome data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chromium" 2>/dev/null || true
sleep 3

# Check if preferences were modified since task start
PREFS_PATH="/home/ga/.config/google-chrome-cdp/Default/Preferences"
BKMK_PATH="/home/ga/.config/google-chrome-cdp/Default/Bookmarks"

PREFS_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$PREFS_PATH" ]; then
    PREFS_MTIME=$(stat -c %Y "$PREFS_PATH" 2>/dev/null || echo "0")
    if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
        PREFS_MODIFIED="true"
    fi
fi

# Copy files to /tmp/ to ensure permissionless extraction by copy_from_env
cp "$PREFS_PATH" /tmp/task_Preferences.json 2>/dev/null || true
cp "$BKMK_PATH" /tmp/task_Bookmarks.json 2>/dev/null || true
chmod 666 /tmp/task_Preferences.json /tmp/task_Bookmarks.json 2>/dev/null || true

# Generate a minimal meta JSON
cat > /tmp/task_meta.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_modified_during_task": $PREFS_MODIFIED
}
EOF

echo "=== Export complete ==="