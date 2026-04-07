#!/bin/bash
set -e
echo "=== Exporting transclusion task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TW_URL="http://localhost:8080"
API_RESULT=$(curl -s "${TW_URL}/recipes/default/tiddlers/Incident%20Response%20Runbook" 2>/dev/null || echo "")

FOUND_SOURCE="none"
API_TITLE=$(echo "$API_RESULT" | jq -r '.title // ""' 2>/dev/null || echo "")
TIDDLER_TEXT=""
TIDDLER_TAGS=""
TIDDLER_PRIORITY=""
FILE_CREATED_DURING_TASK="false"
GUI_SAVE_DETECTED="false"

# Try API first
if [ -n "$API_TITLE" ] && [ "$API_TITLE" != "" ] && [ "$API_TITLE" != "null" ]; then
    FOUND_SOURCE="api"
    TIDDLER_TEXT=$(echo "$API_RESULT" | jq -r '.text // ""' 2>/dev/null || echo "")
    TIDDLER_TAGS=$(echo "$API_RESULT" | jq -r '.tags // ""' 2>/dev/null || echo "")
    TIDDLER_PRIORITY=$(echo "$API_RESULT" | jq -r '.priority // ""' 2>/dev/null || echo "")
fi

# Verify against File System to check timestamps (anti-gaming)
TIDDLER_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "Incident Response Runbook.tid" 2>/dev/null | head -1)

if [ -n "$TIDDLER_FILE" ] && [ -f "$TIDDLER_FILE" ]; then
    if [ "$FOUND_SOURCE" = "none" ]; then
        FOUND_SOURCE="file"
        TIDDLER_TEXT=$(awk '/^$/{found=1; next} found{print}' "$TIDDLER_FILE")
        TIDDLER_TAGS=$(grep -i "^tags:" "$TIDDLER_FILE" | head -1 | sed 's/^tags: *//i')
        TIDDLER_PRIORITY=$(grep -i "^priority:" "$TIDDLER_FILE" | head -1 | sed 's/^priority: *//i')
        API_TITLE=$(grep -i "^title:" "$TIDDLER_FILE" | head -1 | sed 's/^title: *//i')
    fi
    
    # Anti-gaming: Ensure the file is newer than the task start time
    if [ -f /tmp/task_start_time.txt ]; then
        TASK_START=$(cat /tmp/task_start_time.txt)
        FILE_MOD=$(stat -c %Y "$TIDDLER_FILE" 2>/dev/null || echo "0")
        if [ "$FILE_MOD" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Anti-gaming: Check TiddlyWiki server log for GUI save events
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*incident.*response.*runbook" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

# Prepare parsed criteria metrics
HAS_RUNBOOK_TAG="false"
HAS_OPERATIONS_TAG="false"
HAS_TRANSCLUDE_HEALTH="false"
HAS_TRANSCLUDE_FAILOVER="false"
HAS_TRANSCLUDE_ESCALATION="false"
HAS_TRANSCLUDE_REVIEW="false"
PRIORITY_CRITICAL="false"
HEADER_COUNT=0

if [ "$FOUND_SOURCE" != "none" ]; then
    echo "$TIDDLER_TAGS" | grep -qi "Runbook" && HAS_RUNBOOK_TAG="true"
    echo "$TIDDLER_TAGS" | grep -qi "Operations" && HAS_OPERATIONS_TAG="true"
    
    echo "$TIDDLER_TEXT" | grep -qF "{{Service Health Check Procedure}}" && HAS_TRANSCLUDE_HEALTH="true"
    echo "$TIDDLER_TEXT" | grep -qF "{{Database Failover Steps}}" && HAS_TRANSCLUDE_FAILOVER="true"
    echo "$TIDDLER_TEXT" | grep -qF "{{Notification Escalation Matrix}}" && HAS_TRANSCLUDE_ESCALATION="true"
    echo "$TIDDLER_TEXT" | grep -qF "{{Post-Incident Review Template}}" && HAS_TRANSCLUDE_REVIEW="true"
    
    echo "$TIDDLER_PRIORITY" | grep -qi "critical" && PRIORITY_CRITICAL="true"
    
    # TiddlyWiki headers start with ! at the beginning of a line
    HEADER_COUNT=$(echo "$TIDDLER_TEXT" | grep -cE "^!+" 2>/dev/null || echo "0")
fi

ESCAPED_TITLE=$(json_escape "$API_TITLE")
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")
ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")
ESCAPED_PRIORITY=$(json_escape "$TIDDLER_PRIORITY")

JSON_RESULT=$(cat << EOF
{
    "found_source": "$FOUND_SOURCE",
    "title": "$ESCAPED_TITLE",
    "tags": "$ESCAPED_TAGS",
    "text": "$ESCAPED_TEXT",
    "priority": "$ESCAPED_PRIORITY",
    "has_runbook_tag": $HAS_RUNBOOK_TAG,
    "has_operations_tag": $HAS_OPERATIONS_TAG,
    "has_transclude_health": $HAS_TRANSCLUDE_HEALTH,
    "has_transclude_failover": $HAS_TRANSCLUDE_FAILOVER,
    "has_transclude_escalation": $HAS_TRANSCLUDE_ESCALATION,
    "has_transclude_review": $HAS_TRANSCLUDE_REVIEW,
    "header_count": $HEADER_COUNT,
    "priority_critical": $PRIORITY_CRITICAL,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/transclusion_result.json"

echo "Result saved to /tmp/transclusion_result.json"
echo "=== Export complete ==="