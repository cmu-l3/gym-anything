#!/bin/bash
echo "=== Exporting add_tags_to_tiddler result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/add_tags_final.png

TARGET="CRISPR Gene Editing"
INITIAL_TAGS=$(cat /tmp/initial_tags 2>/dev/null || echo "")

# Read current tags from the tiddler file
CURRENT_TAGS=$(get_tiddler_field "$TARGET" "tags")
TIDDLER_EXISTS=$(tiddler_exists "$TARGET")

# Check for each expected tag
HAS_SCIENCE="false"
HAS_BIOLOGY="false"
HAS_GENETICS="false"
HAS_BIOTECHNOLOGY="false"
HAS_NOBEL="false"

if [ -n "$CURRENT_TAGS" ]; then
    echo "$CURRENT_TAGS" | grep -qi "science" && HAS_SCIENCE="true"
    echo "$CURRENT_TAGS" | grep -qi "biology" && HAS_BIOLOGY="true"
    echo "$CURRENT_TAGS" | grep -qi "genetics" && HAS_GENETICS="true"
    echo "$CURRENT_TAGS" | grep -qi "biotechnology" && HAS_BIOTECHNOLOGY="true"
    echo "$CURRENT_TAGS" | grep -qi "nobel" && HAS_NOBEL="true"
fi

# Count total tags (space-separated, with [[multi word]] support)
TAG_COUNT=0
if [ -n "$CURRENT_TAGS" ]; then
    # Count tags accounting for [[multi word tags]]
    TAG_COUNT=$(echo "$CURRENT_TAGS" | grep -oP '(\[\[[^\]]+\]\]|\S+)' | wc -l)
fi

# Check that content was preserved
TIDDLER_TEXT=$(get_tiddler_text "$TARGET")
TEXT_WORD_COUNT=0
HAS_CRISPR_CONTENT="false"
if [ -n "$TIDDLER_TEXT" ]; then
    TEXT_WORD_COUNT=$(echo "$TIDDLER_TEXT" | wc -w)
    echo "$TIDDLER_TEXT" | grep -qi "crispr\|gene.*edit\|cas9" && HAS_CRISPR_CONTENT="true"
fi

ESCAPED_TAGS=$(json_escape "$CURRENT_TAGS")
ESCAPED_INITIAL=$(json_escape "$INITIAL_TAGS")

# Check TiddlyWiki server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*crispr\|Dispatching 'save' task:.*gene.*edit" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "initial_tags": "$ESCAPED_INITIAL",
    "current_tags": "$ESCAPED_TAGS",
    "tag_count": $TAG_COUNT,
    "has_science_tag": $HAS_SCIENCE,
    "has_biology_tag": $HAS_BIOLOGY,
    "has_genetics_tag": $HAS_GENETICS,
    "has_biotechnology_tag": $HAS_BIOTECHNOLOGY,
    "has_nobel_tag": $HAS_NOBEL,
    "content_preserved": $HAS_CRISPR_CONTENT,
    "content_word_count": $TEXT_WORD_COUNT,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/add_tags_result.json"

echo "Result saved to /tmp/add_tags_result.json"
cat /tmp/add_tags_result.json
echo "=== Export complete ==="
