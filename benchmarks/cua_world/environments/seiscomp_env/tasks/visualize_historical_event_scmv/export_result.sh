#!/bin/bash
echo "=== Exporting visualize_historical_event_scmv result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot (for visual debugging context)
take_screenshot /tmp/task_end_screenshot.png

# 2. Check for output screenshot
SCREENSHOT_PATH="/home/ga/scmv_noto_map.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED="false"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED="true"
    fi
fi

# 3. Read config values
# Fallback to system configuration if user configuration is missing
USER_CONFIG="/home/ga/.seiscomp/scmv.cfg"
SYS_CONFIG="$SEISCOMP_ROOT/etc/scmv.cfg"

VISIBLE_TIME_SPAN=$(grep -oP '^\s*events\.visibleTimeSpan\s*=\s*\K.*' "$USER_CONFIG" 2>/dev/null || echo "")
if [ -z "$VISIBLE_TIME_SPAN" ]; then
    VISIBLE_TIME_SPAN=$(grep -oP '^\s*events\.visibleTimeSpan\s*=\s*\K.*' "$SYS_CONFIG" 2>/dev/null || echo "")
fi

RETENTION=$(grep -oP '^\s*events\.retention\s*=\s*\K.*' "$USER_CONFIG" 2>/dev/null || echo "")
if [ -z "$RETENTION" ]; then
    RETENTION=$(grep -oP '^\s*events\.retention\s*=\s*\K.*' "$SYS_CONFIG" 2>/dev/null || echo "")
fi

# Remove trailing/leading whitespaces and carriage returns
VISIBLE_TIME_SPAN=$(echo "$VISIBLE_TIME_SPAN" | tr -d '\r' | xargs)
RETENTION=$(echo "$RETENTION" | tr -d '\r' | xargs)

# 4. Check if scmv is currently running
SCMV_RUNNING="false"
if pgrep -f "$SEISCOMP_ROOT/bin/scmv" > /dev/null; then
    SCMV_RUNNING="true"
fi

# 5. Export JSON
TEMP_JSON=$(mktemp /tmp/scmv_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created_during_task": $SCREENSHOT_CREATED,
    "visible_time_span": "$VISIBLE_TIME_SPAN",
    "retention": "$RETENTION",
    "scmv_running": $SCMV_RUNNING
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="