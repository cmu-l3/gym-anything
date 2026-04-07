#!/bin/bash
echo "=== Exporting create_dynamic_az_glossary result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial state records
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

EXPECTED_TITLE="A-Z Glossary"
GLOSSARY_FOUND="false"
GLOSSARY_TEXT=""
HAS_LIST_WIDGET="false"
HAS_FILTER_ATTR="false"
HAS_TAG_REF="false"
HAS_DYNAMIC_MACRO="false"

# Look for the glossary tiddler
if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    GLOSSARY_FOUND="true"
    GLOSSARY_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
    
    # Analyze content for required dynamic elements (anti-hardcoding check)
    if echo "$GLOSSARY_TEXT" | grep -qi "<$list"; then
        HAS_LIST_WIDGET="true"
    fi
    
    if echo "$GLOSSARY_TEXT" | grep -qi "filter="; then
        HAS_FILTER_ATTR="true"
    fi
    
    if echo "$GLOSSARY_TEXT" | grep -qi "GlossaryTerm"; then
        HAS_TAG_REF="true"
    fi
    
    if echo "$GLOSSARY_TEXT" | grep -qiE "(prefix|splitbefore|all\[current\]|currentTiddler|variable=)"; then
        HAS_DYNAMIC_MACRO="true"
    fi
fi

# Check server logs to verify it was saved via the GUI, not just edited on disk
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*a-z.*glossary" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

# Verify the base terminology tiddlers weren't deleted
TERMS_REMAINING=$(find_tiddlers_with_tag "GlossaryTerm" | wc -l)

ESCAPED_TEXT=$(json_escape "$GLOSSARY_TEXT")

JSON_RESULT=$(cat << EOF
{
    "task_start_time": $TASK_START,
    "initial_tiddler_count": $INITIAL_COUNT,
    "current_tiddler_count": $CURRENT_COUNT,
    "terms_remaining": $TERMS_REMAINING,
    "glossary_found": $GLOSSARY_FOUND,
    "has_list_widget": $HAS_LIST_WIDGET,
    "has_filter_attr": $HAS_FILTER_ATTR,
    "has_tag_ref": $HAS_TAG_REF,
    "has_dynamic_macro": $HAS_DYNAMIC_MACRO,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "glossary_text_preview": "$ESCAPED_TEXT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="