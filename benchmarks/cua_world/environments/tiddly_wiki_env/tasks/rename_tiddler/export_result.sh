#!/bin/bash
echo "=== Exporting rename_tiddler result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/rename_final.png

ORIGINAL_TITLE="Q1 2024 Product Roadmap"
NEW_TITLE="Q1 2024 Engineering Roadmap"

# Check if original still exists
ORIGINAL_EXISTS=$(tiddler_exists "$ORIGINAL_TITLE")

# Check if new title exists
NEW_EXISTS=$(tiddler_exists "$NEW_TITLE")

# Get data from the renamed tiddler
NEW_TAGS=""
NEW_TEXT=""
NEW_WORD_COUNT=0
HAS_ROADMAP_TAG="false"
HAS_PM_TAG="false"
HAS_Q1_TAG="false"
CONTENT_HAS_API="false"
CONTENT_HAS_DASHBOARD="false"
CONTENT_HAS_SPRINT="false"

if [ "$NEW_EXISTS" = "true" ]; then
    NEW_TAGS=$(get_tiddler_field "$NEW_TITLE" "tags")
    NEW_TEXT=$(get_tiddler_text "$NEW_TITLE")
    NEW_WORD_COUNT=$(echo "$NEW_TEXT" | wc -w)

    echo "$NEW_TAGS" | grep -qi "roadmap" && HAS_ROADMAP_TAG="true"
    echo "$NEW_TAGS" | grep -qi "project.management\|Project Management" && HAS_PM_TAG="true"
    echo "$NEW_TAGS" | grep -qi "q1.2024\|Q1 2024" && HAS_Q1_TAG="true"

    echo "$NEW_TEXT" | grep -qi "api\|API" && CONTENT_HAS_API="true"
    echo "$NEW_TEXT" | grep -qi "dashboard" && CONTENT_HAS_DASHBOARD="true"
    echo "$NEW_TEXT" | grep -qi "sprint" && CONTENT_HAS_SPRINT="true"
fi

ORIGINAL_WORD_COUNT=$(cat /tmp/original_word_count 2>/dev/null || echo "0")

ESCAPED_TAGS=$(json_escape "$NEW_TAGS")

# Check TiddlyWiki server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*engineering.*roadmap\|Dispatching 'save' task:.*Q1.*2024" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

JSON_RESULT=$(cat << EOF
{
    "original_exists": $ORIGINAL_EXISTS,
    "new_exists": $NEW_EXISTS,
    "new_tags": "$ESCAPED_TAGS",
    "new_word_count": $NEW_WORD_COUNT,
    "original_word_count": $ORIGINAL_WORD_COUNT,
    "has_roadmap_tag": $HAS_ROADMAP_TAG,
    "has_pm_tag": $HAS_PM_TAG,
    "has_q1_tag": $HAS_Q1_TAG,
    "content_has_api": $CONTENT_HAS_API,
    "content_has_dashboard": $CONTENT_HAS_DASHBOARD,
    "content_has_sprint": $CONTENT_HAS_SPRINT,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/rename_tiddler_result.json"

echo "Result saved to /tmp/rename_tiddler_result.json"
cat /tmp/rename_tiddler_result.json
echo "=== Export complete ==="
