#!/bin/bash
set -euo pipefail

echo "=== Exporting share_screen task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ACTIVE_SHOT="/tmp/screen_share_active.png"
STOPPED_SHOT="/tmp/screen_share_stopped.png"

# 1. Check Active Screenshot
ACTIVE_EXISTS="false"
ACTIVE_SIZE="0"
ACTIVE_CREATED_DURING="false"
ACTIVE_TIME="0"

if [ -f "$ACTIVE_SHOT" ]; then
    ACTIVE_EXISTS="true"
    ACTIVE_SIZE=$(stat -c %s "$ACTIVE_SHOT" 2>/dev/null || echo "0")
    ACTIVE_TIME=$(stat -c %Y "$ACTIVE_SHOT" 2>/dev/null || echo "0")
    if [ "$ACTIVE_TIME" -gt "$TASK_START" ]; then
        ACTIVE_CREATED_DURING="true"
    fi
fi

# 2. Check Stopped Screenshot
STOPPED_EXISTS="false"
STOPPED_SIZE="0"
STOPPED_CREATED_DURING="false"
STOPPED_TIME="0"

if [ -f "$STOPPED_SHOT" ]; then
    STOPPED_EXISTS="true"
    STOPPED_SIZE=$(stat -c %s "$STOPPED_SHOT" 2>/dev/null || echo "0")
    STOPPED_TIME=$(stat -c %Y "$STOPPED_SHOT" 2>/dev/null || echo "0")
    if [ "$STOPPED_TIME" -gt "$TASK_START" ]; then
        STOPPED_CREATED_DURING="true"
    fi
fi

# 3. Compare file hashes (Anti-gaming: ensure they are different images)
IMAGES_DIFFERENT="false"
if [ "$ACTIVE_EXISTS" = "true" ] && [ "$STOPPED_EXISTS" = "true" ]; then
    HASH1=$(md5sum "$ACTIVE_SHOT" | cut -d' ' -f1)
    HASH2=$(md5sum "$STOPPED_SHOT" | cut -d' ' -f1)
    if [ "$HASH1" != "$HASH2" ]; then
        IMAGES_DIFFERENT="true"
    fi
fi

# 4. Chronological Order Check
CORRECT_ORDER="false"
if [ "$ACTIVE_EXISTS" = "true" ] && [ "$STOPPED_EXISTS" = "true" ]; then
    if [ "$STOPPED_TIME" -ge "$ACTIVE_TIME" ]; then
        CORRECT_ORDER="true"
    fi
fi

# 5. Check if agent is still in the meeting (Application State)
# We can check window title of Firefox
FIREFOX_TITLE=$(DISPLAY=:1 xdotool search --class firefox getwindowname 2>/dev/null || echo "unknown")
IN_MEETING="false"
if [[ "$FIREFOX_TITLE" == *"QuarterlyPlanningSync"* ]]; then
    IN_MEETING="true"
fi

# Capture final system state for VLM context if needed
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "active_screenshot": {
        "exists": $ACTIVE_EXISTS,
        "size": $ACTIVE_SIZE,
        "created_during_task": $ACTIVE_CREATED_DURING,
        "timestamp": $ACTIVE_TIME
    },
    "stopped_screenshot": {
        "exists": $STOPPED_EXISTS,
        "size": $STOPPED_SIZE,
        "created_during_task": $STOPPED_CREATED_DURING,
        "timestamp": $STOPPED_TIME
    },
    "images_different": $IMAGES_DIFFERENT,
    "chronological_order": $CORRECT_ORDER,
    "in_meeting_at_end": $IN_MEETING,
    "firefox_title": "$FIREFOX_TITLE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="