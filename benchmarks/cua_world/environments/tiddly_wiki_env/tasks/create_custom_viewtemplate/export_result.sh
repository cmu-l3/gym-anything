#!/bin/bash
echo "=== Exporting create_custom_viewtemplate result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/viewtemplate_final.png

# Check if seed tiddlers were modified (anti-gaming check)
SEED1_CURRENT=$(md5sum "$TIDDLER_DIR/Attention Is All You Need.tid" 2>/dev/null | awk '{print $1}')
SEED2_CURRENT=$(md5sum "$TIDDLER_DIR/MapReduce.tid" 2>/dev/null | awk '{print $1}')
SEED3_CURRENT=$(md5sum "$TIDDLER_DIR/ResNet.tid" 2>/dev/null | awk '{print $1}')

SEED1_ORIGINAL=$(cat /tmp/seed1_hash 2>/dev/null)
SEED2_ORIGINAL=$(cat /tmp/seed2_hash 2>/dev/null)
SEED3_ORIGINAL=$(cat /tmp/seed3_hash 2>/dev/null)

SEEDS_UNMODIFIED="true"
if [ "$SEED1_CURRENT" != "$SEED1_ORIGINAL" ] || [ "$SEED2_CURRENT" != "$SEED2_ORIGINAL" ] || [ "$SEED3_CURRENT" != "$SEED3_ORIGINAL" ]; then
    SEEDS_UNMODIFIED="false"
fi

# Search for the custom ViewTemplate tiddler
TEMPLATE_FOUND="false"
TEMPLATE_TITLE=""
TEMPLATE_TAGS=""
TEMPLATE_TEXT=""

for f in "$TIDDLER_DIR"/*.tid; do
    [ -e "$f" ] || continue
    
    # Check if the file contains the required system tag
    if grep -q "^tags:.*\$:/tags/ViewTemplate" "$f"; then
        TEMPLATE_FOUND="true"
        TEMPLATE_TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
        TEMPLATE_TAGS=$(grep "^tags:" "$f" | head -1 | sed 's/^tags: *//')
        TEMPLATE_TEXT=$(awk '/^$/{found=1; next} found{print}' "$f")
        break
    fi
done

# Perform basic text analysis in bash before passing to Python verifier
HAS_CONDITIONAL_LOGIC="false"
HAS_ALL_FIELDS="false"

if [ "$TEMPLATE_FOUND" = "true" ]; then
    # Check for conditional logic targeting Paper
    if echo "$TEMPLATE_TEXT" | grep -qi "tag\[Paper\]\|tag<Paper>\|tag=Paper"; then
        HAS_CONDITIONAL_LOGIC="true"
    fi
    
    # Check for the required fields
    FIELD_COUNT=0
    echo "$TEMPLATE_TEXT" | grep -q "author" && FIELD_COUNT=$((FIELD_COUNT + 1))
    echo "$TEMPLATE_TEXT" | grep -q "journal" && FIELD_COUNT=$((FIELD_COUNT + 1))
    echo "$TEMPLATE_TEXT" | grep -q "year" && FIELD_COUNT=$((FIELD_COUNT + 1))
    echo "$TEMPLATE_TEXT" | grep -q "doi" && FIELD_COUNT=$((FIELD_COUNT + 1))
    
    if [ "$FIELD_COUNT" -eq 4 ]; then
        HAS_ALL_FIELDS="true"
    fi
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

ESCAPED_TITLE=$(json_escape "$TEMPLATE_TITLE")
ESCAPED_TAGS=$(json_escape "$TEMPLATE_TAGS")
ESCAPED_TEXT=$(json_escape "$TEMPLATE_TEXT")

JSON_RESULT=$(cat << EOF
{
    "template_found": $TEMPLATE_FOUND,
    "template_title": "$ESCAPED_TITLE",
    "template_tags": "$ESCAPED_TAGS",
    "template_text": "$ESCAPED_TEXT",
    "seeds_unmodified": $SEEDS_UNMODIFIED,
    "has_conditional_logic": $HAS_CONDITIONAL_LOGIC,
    "has_all_fields_mentioned": $HAS_ALL_FIELDS,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/viewtemplate_result.json"

echo "Result saved to /tmp/viewtemplate_result.json"
cat /tmp/viewtemplate_result.json
echo "=== Export complete ==="