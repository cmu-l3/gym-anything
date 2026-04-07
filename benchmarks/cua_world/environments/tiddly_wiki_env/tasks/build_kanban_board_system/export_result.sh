#!/bin/bash
echo "=== Exporting build_kanban_board_system result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/kanban_final.png

# Check data integrity (were the seed tasks deleted?)
INITIAL_TASK_COUNT=$(cat /tmp/initial_task_count 2>/dev/null || echo "6")
CURRENT_TASK_COUNT=$(find_tiddlers_with_tag "Task" | wc -l)

# Search for the Kanban Dashboard tiddler
EXPECTED_TITLE="Kanban Dashboard"
DASHBOARD_FOUND="false"
DASHBOARD_TEXT=""
DASHBOARD_MTIME="0"
CREATED_DURING_TASK="false"

if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    DASHBOARD_FOUND="true"
    DASHBOARD_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
    
    # Check if created during task
    # Find the actual file path
    SANITIZED=$(echo "$EXPECTED_TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
    FILE_PATH="$TIDDLER_DIR/${SANITIZED}.tid"
    if [ ! -f "$FILE_PATH" ]; then
        FILE_PATH=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${SANITIZED}.tid" 2>/dev/null | head -1)
    fi
    
    if [ -f "$FILE_PATH" ]; then
        DASHBOARD_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        if [ "$DASHBOARD_MTIME" -gt "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
    fi
fi

# Check TiddlyWiki server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*kanban" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build JSON safely
ESCAPED_TEXT=$(json_escape "$DASHBOARD_TEXT")

JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "dashboard_found": $DASHBOARD_FOUND,
    "dashboard_text": "$ESCAPED_TEXT",
    "created_during_task": $CREATED_DURING_TASK,
    "initial_task_count": $INITIAL_TASK_COUNT,
    "current_task_count": $CURRENT_TASK_COUNT,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/kanban_result.json"

echo "Result saved to /tmp/kanban_result.json"
cat /tmp/kanban_result.json
echo "=== Export complete ==="