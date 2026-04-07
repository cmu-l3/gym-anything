#!/bin/bash
set -euo pipefail

echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing Thunderbird (Crucial for VLM verification)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

# Close Thunderbird gracefully so it flushes layout preferences to prefs.js
echo "Closing Thunderbird to flush preferences to disk..."
su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
sleep 3
pkill -f "thunderbird" 2>/dev/null || true
sleep 1

PROFILE_DIR="/home/ga/.thunderbird/default-release"
PREFS_FILE="${PROFILE_DIR}/prefs.js"

# Check the dynamic pane configuration preference
# 0 = Classic, 1 = Wide, 2 = Vertical
PANE_CONFIG="0"
if [ -f "$PREFS_FILE" ]; then
    PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
    
    # Extract the preference value
    EXTRACTED_VAL=$(grep "\"mail.pane_config.dynamic\"" "$PREFS_FILE" 2>/dev/null | grep -oE "[0-9]+" | head -1 || echo "")
    if [ -n "$EXTRACTED_VAL" ]; then
        PANE_CONFIG="$EXTRACTED_VAL"
    fi
else
    PREFS_MTIME="0"
fi

# Determine if prefs were modified during task
PREFS_MODIFIED="false"
if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
    PREFS_MODIFIED="true"
fi

# Export data to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_modified_during_task": $PREFS_MODIFIED,
    "pane_config_dynamic": $PANE_CONFIG,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="