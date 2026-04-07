#!/bin/bash
echo "=== Exporting create_postmortem_dashboard_button result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

DASHBOARD_TITLE="Post-Mortem Dashboard"
DASHBOARD_EXISTS=$(tiddler_exists "$DASHBOARD_TITLE")

DASHBOARD_TAGS=""
DASHBOARD_TEXT=""
TEMPLATE_TEXT=""
TEMPLATE_TITLE=""

if [ "$DASHBOARD_EXISTS" = "true" ]; then
    DASHBOARD_TAGS=$(get_tiddler_field "$DASHBOARD_TITLE" "tags")
    DASHBOARD_TEXT=$(get_tiddler_text "$DASHBOARD_TITLE")
    
    # Search for a template tiddler if they used Option B
    # A template would likely have the boilerplate headings
    for f in "$TIDDLER_DIR"/*.tid; do
        if grep -q "!! Summary" "$f" && grep -q "!! Root Cause" "$f"; then
            # Ignore the seed data files
            if ! grep -q "Cloudflare\|AWS Kinesis\|Fastly\|GitHub Database\|Facebook BGP" "$f"; then
                TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
                # If it's not the dashboard itself
                if [ "$TITLE" != "$DASHBOARD_TITLE" ]; then
                    TEMPLATE_TITLE="$TITLE"
                    TEMPLATE_TEXT=$(awk '/^$/{found=1; next} found{print}' "$f")
                    
                    # Look for fields in the template file header
                    TEMPLATE_FIELDS=$(awk '/^$/{exit} {print}' "$f")
                    TEMPLATE_TEXT="${TEMPLATE_FIELDS}\n\n${TEMPLATE_TEXT}"
                    break
                fi
            fi
        fi
    done
fi

# Check for a newly created draft (if they actually clicked the button)
DRAFT_CREATED="false"
if ls "$TIDDLER_DIR"/Draft_of_*.tid 1> /dev/null 2>&1; then
    DRAFT_CREATED="true"
fi

# Check logs for GUI usage
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*Post-Mortem" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape JSON
ESCAPED_TAGS=$(json_escape "$DASHBOARD_TAGS")
ESCAPED_TEXT=$(json_escape "$DASHBOARD_TEXT")
ESCAPED_TEMPLATE_TITLE=$(json_escape "$TEMPLATE_TITLE")
ESCAPED_TEMPLATE_TEXT=$(json_escape "$TEMPLATE_TEXT")

JSON_RESULT=$(cat << EOF
{
    "dashboard_exists": $DASHBOARD_EXISTS,
    "dashboard_tags": "$ESCAPED_TAGS",
    "dashboard_text": "$ESCAPED_TEXT",
    "template_title": "$ESCAPED_TEMPLATE_TITLE",
    "template_text": "$ESCAPED_TEMPLATE_TEXT",
    "draft_created": $DRAFT_CREATED,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/postmortem_task_result.json"

echo "Result saved to /tmp/postmortem_task_result.json"
echo "=== Export complete ==="