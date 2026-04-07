#!/usr/bin/env bash
set -e

echo "=== Exporting Smart Building Control Center Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing Chrome
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Chrome was running
APP_RUNNING=$(pgrep -f "chrome" > /dev/null && echo "true" || echo "false")

# Gracefully close Chrome to flush SQLite databases (History, Web Data, etc.) and Preferences to disk
echo "Closing Chrome to flush data to disk..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# ============================================================
# Check for Desktop Shortcut (.desktop files)
# ============================================================
DESKTOP_SHORTCUT_FOUND="false"
DESKTOP_SHORTCUT_URL=""

# Look through all .desktop files on the desktop
for f in /home/ga/Desktop/*.desktop; do
    if [ -f "$f" ]; then
        # Check if the Exec or URL line contains grainger
        if grep -qi "grainger.com" "$f"; then
            DESKTOP_SHORTCUT_FOUND="true"
            DESKTOP_SHORTCUT_URL=$(grep -i "grainger.com" "$f" | head -n 1)
            break
        fi
    fi
done

# ============================================================
# Generate JSON Result payload
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "desktop_shortcut_found": $DESKTOP_SHORTCUT_FOUND,
    "desktop_shortcut_url": "$DESKTOP_SHORTCUT_URL",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="