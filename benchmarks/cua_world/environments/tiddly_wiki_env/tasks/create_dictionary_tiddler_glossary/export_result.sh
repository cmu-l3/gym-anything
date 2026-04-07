#!/bin/bash
echo "=== Exporting create_dictionary_tiddler_glossary result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM or evidence
take_screenshot /tmp/task_final.png

DICT_TITLE="METAR Codes"
REF_TITLE="Weather Code Reference"

DICT_EXISTS=$(tiddler_exists "$DICT_TITLE")
REF_EXISTS=$(tiddler_exists "$REF_TITLE")

DICT_TYPE=""
DICT_TEXT=""
if [ "$DICT_EXISTS" = "true" ]; then
    DICT_TYPE=$(get_tiddler_field "$DICT_TITLE" "type")
    DICT_TEXT=$(get_tiddler_text "$DICT_TITLE")
fi

REF_TAGS=""
REF_TEXT=""
if [ "$REF_EXISTS" = "true" ]; then
    REF_TAGS=$(get_tiddler_field "$REF_TITLE" "tags")
    REF_TEXT=$(get_tiddler_text "$REF_TITLE")
fi

# Check TiddlyWiki server log for GUI save events (Anti-gaming check)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*METAR" /home/ga/tiddlywiki.log 2>/dev/null || grep -qi "Dispatching 'save' task:.*Weather" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape text and tags for valid JSON encoding
ESCAPED_DICT_TYPE=$(json_escape "$DICT_TYPE")
ESCAPED_DICT_TEXT=$(json_escape "$DICT_TEXT")
ESCAPED_REF_TAGS=$(json_escape "$REF_TAGS")
ESCAPED_REF_TEXT=$(json_escape "$REF_TEXT")

# Build the results JSON
JSON_RESULT=$(cat << EOF
{
    "dict_exists": $DICT_EXISTS,
    "ref_exists": $REF_EXISTS,
    "dict_type": "$ESCAPED_DICT_TYPE",
    "dict_text": "$ESCAPED_DICT_TEXT",
    "ref_tags": "$ESCAPED_REF_TAGS",
    "ref_text": "$ESCAPED_REF_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="