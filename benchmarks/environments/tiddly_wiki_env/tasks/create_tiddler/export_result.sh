#!/bin/bash
echo "=== Exporting create_tiddler result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_tiddler_final.png

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

# Search for the expected tiddler
EXPECTED_TITLE="Machine Learning Pipeline Architecture"
TIDDLER_FOUND="false"
TIDDLER_TITLE=""
TIDDLER_TAGS=""
TIDDLER_TEXT=""
WORD_COUNT=0

# Try exact title match
if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    TIDDLER_FOUND="true"
    TIDDLER_TITLE="$EXPECTED_TITLE"
    TIDDLER_TAGS=$(get_tiddler_field "$EXPECTED_TITLE" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
    WORD_COUNT=$(echo "$TIDDLER_TEXT" | wc -w)
fi

# Try partial match if exact not found
if [ "$TIDDLER_FOUND" = "false" ]; then
    # Search for tiddlers containing "Machine Learning" or "Pipeline" in title
    MATCH_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -newer /tmp/initial_tiddler_count 2>/dev/null | while IFS= read -r f; do
        TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
        if echo "$TITLE" | grep -qi "machine.*learning\|pipeline"; then
            echo "$f"
            break
        fi
    done)

    if [ -n "$MATCH_FILE" ]; then
        TIDDLER_FOUND="true"
        TIDDLER_TITLE=$(grep "^title:" "$MATCH_FILE" | head -1 | sed 's/^title: *//')
        TIDDLER_TAGS=$(grep "^tags:" "$MATCH_FILE" | head -1 | sed 's/^tags: *//')
        TIDDLER_TEXT=$(awk '/^$/{found=1; next} found{print}' "$MATCH_FILE")
        WORD_COUNT=$(echo "$TIDDLER_TEXT" | wc -w)
    fi
fi

# Check for keywords in text
HAS_DATA="false"
HAS_MODEL="false"
HAS_TRAINING="false"
HAS_PIPELINE="false"
HAS_FORMATTING="false"

if [ -n "$TIDDLER_TEXT" ]; then
    echo "$TIDDLER_TEXT" | grep -qi "data" && HAS_DATA="true"
    echo "$TIDDLER_TEXT" | grep -qi "model" && HAS_MODEL="true"
    echo "$TIDDLER_TEXT" | grep -qi "training\|train" && HAS_TRAINING="true"
    echo "$TIDDLER_TEXT" | grep -qi "pipeline" && HAS_PIPELINE="true"
    # Check for TiddlyWiki formatting - require at least 2 distinct formatting types
    # to prevent trivial gaming with a single bullet point
    FMT_COUNT=0
    echo "$TIDDLER_TEXT" | grep -qE "^!" && FMT_COUNT=$((FMT_COUNT + 1))
    echo "$TIDDLER_TEXT" | grep -qE "^\*" && FMT_COUNT=$((FMT_COUNT + 1))
    echo "$TIDDLER_TEXT" | grep -qE "''" && FMT_COUNT=$((FMT_COUNT + 1))
    echo "$TIDDLER_TEXT" | grep -qE "//" && FMT_COUNT=$((FMT_COUNT + 1))
    echo "$TIDDLER_TEXT" | grep -qE "\[\[" && FMT_COUNT=$((FMT_COUNT + 1))
    [ $FMT_COUNT -ge 2 ] && HAS_FORMATTING="true"
fi

# Check tags
HAS_TECHNOLOGY_TAG="false"
HAS_ML_TAG="false"
if [ -n "$TIDDLER_TAGS" ]; then
    echo "$TIDDLER_TAGS" | grep -qi "technology" && HAS_TECHNOLOGY_TAG="true"
    echo "$TIDDLER_TAGS" | grep -qi "machinelearning\|machine.learning" && HAS_ML_TAG="true"
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*machine.*learning\|Dispatching 'save' task:.*pipeline" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build JSON result
ESCAPED_TITLE=$(json_escape "$TIDDLER_TITLE")
ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")

JSON_RESULT=$(cat << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "tiddler_found": $TIDDLER_FOUND,
    "tiddler_title": "$ESCAPED_TITLE",
    "tiddler_tags": "$ESCAPED_TAGS",
    "word_count": $WORD_COUNT,
    "has_data_keyword": $HAS_DATA,
    "has_model_keyword": $HAS_MODEL,
    "has_training_keyword": $HAS_TRAINING,
    "has_pipeline_keyword": $HAS_PIPELINE,
    "has_formatting": $HAS_FORMATTING,
    "has_technology_tag": $HAS_TECHNOLOGY_TAG,
    "has_ml_tag": $HAS_ML_TAG,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/create_tiddler_result.json"

echo "Result saved to /tmp/create_tiddler_result.json"
cat /tmp/create_tiddler_result.json
echo "=== Export complete ==="
