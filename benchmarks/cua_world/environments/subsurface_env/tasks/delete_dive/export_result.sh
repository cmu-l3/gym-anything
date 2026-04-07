#!/bin/bash
set -e
echo "=== Exporting delete_dive task results ==="

export DISPLAY="${DISPLAY:-:1}"
DIVE_FILE="/home/ga/Documents/dives.ssrf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Read baseline setup data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_dive_count.txt 2>/dev/null || echo "0")
TARGET_DATE=$(cat /tmp/target_dive_date.txt 2>/dev/null || echo "")
TARGET_TIME=$(cat /tmp/target_dive_time.txt 2>/dev/null || echo "")

# Gather final state info
FILE_EXISTS="false"
VALID_XML="false"
CURRENT_COUNT=0
TARGET_MATCH_COUNT=0
FILE_MTIME=0

if [ -f "$DIVE_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$DIVE_FILE" 2>/dev/null || echo "0")
    
    # Check if file is parseable
    if xmlstarlet sel -t -v "count(//dive)" "$DIVE_FILE" >/dev/null 2>&1; then
        VALID_XML="true"
        CURRENT_COUNT=$(xmlstarlet sel -t -v "count(//dive)" "$DIVE_FILE" 2>/dev/null || echo "0")
        
        # Check if the exact target dive still exists
        if [ -n "$TARGET_DATE" ] && [ -n "$TARGET_TIME" ]; then
            TARGET_MATCH_COUNT=$(xmlstarlet sel -t -v "count(//dive[@date='$TARGET_DATE' and @time='$TARGET_TIME'])" "$DIVE_FILE" 2>/dev/null || echo "0")
        fi
    fi
fi

# Check if application was running
APP_RUNNING="false"
if pgrep -f "subsurface" > /dev/null; then
    APP_RUNNING="true"
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "valid_xml": $VALID_XML,
    "file_mtime": $FILE_MTIME,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "target_date": "$TARGET_DATE",
    "target_time": "$TARGET_TIME",
    "target_match_count": $TARGET_MATCH_COUNT,
    "app_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="