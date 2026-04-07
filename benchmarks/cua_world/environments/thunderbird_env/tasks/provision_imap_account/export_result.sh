#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing Thunderbird
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Close Thunderbird gracefully so it flushes prefs.js to disk
echo "Closing Thunderbird to flush preferences..."
close_thunderbird

# Fallback to ensure it's fully closed
pkill -f "thunderbird" 2>/dev/null || true
sleep 2

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Find the profile dir
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -name "*.default*" -o -name "default-release" | head -n 1)
PREFS_FILE="$PROFILE_DIR/prefs.js"

PREFS_MTIME=0
if [ -f "$PREFS_FILE" ]; then
    PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
fi

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_path": "$PREFS_FILE",
    "prefs_mtime": $PREFS_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location allowing verifier to read
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="