#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Ensure Thunderbird saves preferences by sending a graceful flush
# Alternatively, sleep to allow periodic writes
sleep 2

# Target profile directory
TB_PROFILE="/home/ga/.thunderbird/default-release"

EXTENSIONS_JSON="$TB_PROFILE/extensions.json"
PREFS_JS="$TB_PROFILE/prefs.js"

EXTENSIONS_EXISTS="false"
PREFS_EXISTS="false"
PREFS_MTIME=0

# Copy extensions.json
if [ -f "$EXTENSIONS_JSON" ]; then
    EXTENSIONS_EXISTS="true"
    cp "$EXTENSIONS_JSON" /tmp/extensions.json
    chmod 666 /tmp/extensions.json
fi

# Copy prefs.js
if [ -f "$PREFS_JS" ]; then
    PREFS_EXISTS="true"
    PREFS_MTIME=$(stat -c %Y "$PREFS_JS" 2>/dev/null || echo "0")
    cp "$PREFS_JS" /tmp/prefs.js
    chmod 666 /tmp/prefs.js
fi

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "extensions_exists": $EXTENSIONS_EXISTS,
    "prefs_exists": $PREFS_EXISTS,
    "prefs_mtime": $PREFS_MTIME,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="