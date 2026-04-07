#!/bin/bash
set -e
echo "=== Exporting create_project_timeline result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

INITIAL_COUNT=$(cat /tmp/initial_tiddler_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

# Collect data about the 5 milestones
declare -a TITLES=("IRB Protocol Submission" "Equipment Procurement" "Participant Recruitment Phase 1" "Interim Data Analysis" "Year 1 Progress Report to NIH")

DETAILS="{"
for i in "${!TITLES[@]}"; do
    title="${TITLES[$i]}"
    exists=$(tiddler_exists "$title")
    
    if [ "$exists" = "true" ]; then
        due_date=$(get_tiddler_field "$title" "due-date" | tr -d '\r\n')
        status=$(get_tiddler_field "$title" "status" | tr -d '\r\n')
        tags=$(get_tiddler_field "$title" "tags" | tr -d '\r\n')
        
        # Escape strings
        esc_due=$(json_escape "$due_date")
        esc_status=$(json_escape "$status")
        esc_tags=$(json_escape "$tags")
        
        DETAILS="$DETAILS\"milestone_$i\": {\"exists\": true, \"due_date\": \"$esc_due\", \"status\": \"$esc_status\", \"tags\": \"$esc_tags\"}"
    else
        DETAILS="$DETAILS\"milestone_$i\": {\"exists\": false, \"due_date\": \"\", \"status\": \"\", \"tags\": \"\"}"
    fi
    
    if [ $i -lt 4 ]; then
        DETAILS="$DETAILS, "
    fi
done
DETAILS="$DETAILS}"

# Collect data about Project Timeline
TIMELINE_EXISTS=$(tiddler_exists "Project Timeline")
TIMELINE_TEXT=""
if [ "$TIMELINE_EXISTS" = "true" ]; then
    # Get both text and fields area to search for $list and filters
    TIMELINE_TEXT=$(get_tiddler_content "Project Timeline")
fi

ESCAPED_TIMELINE_TEXT=$(json_escape "$TIMELINE_TEXT")

# Check GUI save
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*irb\|Dispatching 'save' task:.*equipment\|Dispatching 'save' task:.*timeline\|Dispatching 'save' task:.*recruitment\|Dispatching 'save' task:.*analysis\|Dispatching 'save' task:.*progress" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

# Build JSON Result
JSON_RESULT=$(cat << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "milestones": $DETAILS,
    "timeline_exists": $TIMELINE_EXISTS,
    "timeline_content": "$ESCAPED_TIMELINE_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/project_timeline_result.json"

echo "Result saved to /tmp/project_timeline_result.json"
cat /tmp/project_timeline_result.json
echo "=== Export complete ==="