#!/bin/bash
echo "=== Exporting configure_junk_and_classify results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot showing end state
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Thunderbird was running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Safely close Thunderbird so it flushes all mbox and prefs.js changes to disk
echo "Closing Thunderbird to flush data to disk..."
close_thunderbird
sleep 3

# Wait briefly for disk I/O
sleep 2

# Verify files exist before creating JSON
PREFS_EXISTS="false"
if [ -f "/home/ga/.thunderbird/default-release/prefs.js" ]; then
    PREFS_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "prefs_exists": $PREFS_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="