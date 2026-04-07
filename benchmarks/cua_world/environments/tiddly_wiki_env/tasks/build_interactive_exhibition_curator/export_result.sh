#!/bin/bash
echo "=== Exporting Exhibition Curator result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/curator_final.png

# Extract Dashboard Data
BUILDER_TITLE="Exhibition Builder"
BUILDER_EXISTS=$(tiddler_exists "$BUILDER_TITLE")
BUILDER_TEXT=""
if [ "$BUILDER_EXISTS" = "true" ]; then
    BUILDER_TEXT=$(get_tiddler_text "$BUILDER_TITLE")
fi

# Widget/Syntax Checks on the Dashboard Code
HAS_LIST_WIDGET=$(echo "$BUILDER_TEXT" | grep -qi "<\$list" && echo "true" || echo "false")
HAS_BUTTON_WIDGET=$(echo "$BUILDER_TEXT" | grep -qi "<\$button" && echo "true" || echo "false")
HAS_LISTOPS_WIDGET=$(echo "$BUILDER_TEXT" | grep -qi "<\$action-listops" && echo "true" || echo "false")
HAS_COUNT_WIDGET=$(echo "$BUILDER_TEXT" | grep -qi "<\$count" && echo "true" || echo "false")
TARGETS_EXHIBITION=$(echo "$BUILDER_TEXT" | grep -qi "Exhibition: Daily Life" && echo "true" || echo "false")
TARGETS_LIST_FIELD=$(echo "$BUILDER_TEXT" | grep -qi "list" && echo "true" || echo "false")
HAS_SUBTRACTION=$(echo "$BUILDER_TEXT" | grep -qi -- "-\[" && echo "true" || echo "false")

# Extract Target Data
TARGET_TITLE="Exhibition: Daily Life"
TARGET_EXISTS=$(tiddler_exists "$TARGET_TITLE")
TARGET_LIST=""
if [ "$TARGET_EXISTS" = "true" ]; then
    TARGET_LIST=$(get_tiddler_field "$TARGET_TITLE" "list")
fi

# Detect Server Save Activity (Anti-gaming check)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    # Look for the target list being updated through the API/GUI rather than file edits
    if grep -qi "Dispatching 'save' task:.*Exhibition:.*Daily.*Life" /home/ga/tiddlywiki.log; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape wikitext for JSON payload
ESCAPED_BUILDER_TEXT=$(json_escape "$BUILDER_TEXT")
ESCAPED_TARGET_LIST=$(json_escape "$TARGET_LIST")

JSON_RESULT=$(cat << EOF
{
    "builder_exists": $BUILDER_EXISTS,
    "builder_text": "$ESCAPED_BUILDER_TEXT",
    "has_list_widget": $HAS_LIST_WIDGET,
    "has_button_widget": $HAS_BUTTON_WIDGET,
    "has_listops_widget": $HAS_LISTOPS_WIDGET,
    "has_count_widget": $HAS_COUNT_WIDGET,
    "targets_exhibition": $TARGETS_EXHIBITION,
    "targets_list_field": $TARGETS_LIST_FIELD,
    "has_subtraction": $HAS_SUBTRACTION,
    "target_exists": $TARGET_EXISTS,
    "target_list_field": "$ESCAPED_TARGET_LIST",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/curator_result.json"

echo "Result saved to /tmp/curator_result.json"
echo "=== Export complete ==="