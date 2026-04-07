#!/bin/bash
echo "=== Exporting build_dynamic_manuscript_compiler result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TARGET="Manuscript Compiler"

TIDDLER_EXISTS=$(tiddler_exists "$TARGET")
LIST_FIELD=""
BODY_TEXT=""
HAS_LIST_WIDGET="false"
HAS_CONDITIONAL_STATUS="false"
HAS_TRANSCLUSION="false"

if [ "$TIDDLER_EXISTS" = "true" ]; then
    LIST_FIELD=$(get_tiddler_field "$TARGET" "list")
    BODY_TEXT=$(get_tiddler_text "$TARGET")
    
    # Check for <$list filter="[list[]]"> or similar list iteration
    if echo "$BODY_TEXT" | grep -qi "<\$list.*list\[\].*>"; then
        HAS_LIST_WIDGET="true"
    elif echo "$BODY_TEXT" | grep -qi "<\$list.*enlist.*>"; then
        HAS_LIST_WIDGET="true"
    fi
    
    # Check for conditional logic based on status
    if echo "$BODY_TEXT" | grep -qi "status\[draft\]\|status\[outline\]\|field:status.*draft\|match.*status.*draft"; then
        HAS_CONDITIONAL_STATUS="true"
    fi
    
    # Check for transclusion widget or transclusion syntax {{!!text}} / <$transclude>
    if echo "$BODY_TEXT" | grep -qi "<\$transclude\|{{!!text}}\|{{currentTiddler}}"; then
        HAS_TRANSCLUSION="true"
    fi
fi

# Determine if the file was created during the task run via GUI
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*manuscript.*compiler" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Export all metrics to JSON
ESCAPED_LIST=$(json_escape "$LIST_FIELD")
ESCAPED_BODY=$(json_escape "$BODY_TEXT")

JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "list_field": "$ESCAPED_LIST",
    "body_text": "$ESCAPED_BODY",
    "has_list_widget": $HAS_LIST_WIDGET,
    "has_conditional_status": $HAS_CONDITIONAL_STATUS,
    "has_transclusion": $HAS_TRANSCLUSION,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/manuscript_task_result.json"

echo "Result saved to /tmp/manuscript_task_result.json"
cat /tmp/manuscript_task_result.json
echo "=== Export complete ==="