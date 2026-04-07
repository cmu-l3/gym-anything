#!/bin/bash
echo "=== Exporting create_interactive_checklist result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/checklist_final.png

# Target Dashboard Tiddler
DASHBOARD_TITLE="Jane Doe Onboarding"
CHECKLIST_EXISTS=$(tiddler_exists "$DASHBOARD_TITLE")
CHECKLIST_TAGS=""
CHECKLIST_TEXT=""

if [ "$CHECKLIST_EXISTS" = "true" ]; then
    CHECKLIST_TAGS=$(get_tiddler_field "$DASHBOARD_TITLE" "tags")
    CHECKLIST_TEXT=$(get_tiddler_text "$DASHBOARD_TITLE")
fi

# Target Task Tiddlers
STATUS_LAPTOP=$(get_tiddler_field "Task: Order Laptop" "status")
STATUS_EMAIL=$(get_tiddler_field "Task: Create Email Account" "status")
STATUS_BADGE=$(get_tiddler_field "Task: Building Access Badge" "status")
STATUS_BENEFITS=$(get_tiddler_field "Task: Benefits Enrollment" "status")

# Check TiddlyWiki server log for GUI save events (anti-gaming: did they use the UI?)
GUI_MUTATION_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    # Look for saves of the specific task tiddlers via the browser
    if grep -q "Dispatching 'save' task: Task: Order Laptop" /home/ga/tiddlywiki.log 2>/dev/null || \
       grep -q "Dispatching 'save' task: Task: Create Email Account" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_MUTATION_DETECTED="true"
    fi
fi

# Escape JSON values
ESCAPED_TAGS=$(json_escape "$CHECKLIST_TAGS")
ESCAPED_TEXT=$(json_escape "$CHECKLIST_TEXT")

# Build the result JSON
JSON_RESULT=$(cat << EOF
{
    "checklist_exists": $CHECKLIST_EXISTS,
    "checklist_tags": "$ESCAPED_TAGS",
    "checklist_text": "$ESCAPED_TEXT",
    "status_laptop": "${STATUS_LAPTOP:-missing}",
    "status_email": "${STATUS_EMAIL:-missing}",
    "status_badge": "${STATUS_BADGE:-missing}",
    "status_benefits": "${STATUS_BENEFITS:-missing}",
    "gui_mutation_detected": $GUI_MUTATION_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/checklist_result.json"

echo "Result saved to /tmp/checklist_result.json"
cat /tmp/checklist_result.json
echo "=== Export complete ==="