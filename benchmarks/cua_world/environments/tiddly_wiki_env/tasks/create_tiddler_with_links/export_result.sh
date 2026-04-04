#!/bin/bash
echo "=== Exporting create_tiddler_with_links result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/links_final.png

INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

EXPECTED_TITLE="RESTful API Design Guide"
TIDDLER_FOUND="false"
TIDDLER_TITLE=""
TIDDLER_TAGS=""
TIDDLER_TEXT=""
WORD_COUNT=0

# Try exact match
if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    TIDDLER_FOUND="true"
    TIDDLER_TITLE="$EXPECTED_TITLE"
    TIDDLER_TAGS=$(get_tiddler_field "$EXPECTED_TITLE" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
    WORD_COUNT=$(echo "$TIDDLER_TEXT" | wc -w)
fi

# Try partial match
if [ "$TIDDLER_FOUND" = "false" ]; then
    MATCH_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -newer /tmp/initial_tiddler_count 2>/dev/null | while IFS= read -r f; do
        TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
        if echo "$TITLE" | grep -qi "restful.*api\|api.*design.*guide"; then
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

# Check for internal links in the text
HAS_AGILE_LINK="false"
HAS_VCS_LINK="false"
HAS_ANY_LINK="false"
LINK_COUNT=0

if [ -n "$TIDDLER_TEXT" ]; then
    # TiddlyWiki links use [[Title]] syntax
    echo "$TIDDLER_TEXT" | grep -q "\[\[Agile Methodology Overview\]\]" && HAS_AGILE_LINK="true"
    echo "$TIDDLER_TEXT" | grep -q "\[\[Version Control Best Practices\]\]" && HAS_VCS_LINK="true"
    # Count all internal links
    LINK_COUNT=$(echo "$TIDDLER_TEXT" | grep -oP '\[\[[^\]]+\]\]' | wc -l)
    [ $LINK_COUNT -gt 0 ] && HAS_ANY_LINK="true"
fi

# Check for keywords
HAS_REST="false"
HAS_API="false"
HAS_HTTP="false"

if [ -n "$TIDDLER_TEXT" ]; then
    echo "$TIDDLER_TEXT" | grep -qi "rest\|restful" && HAS_REST="true"
    echo "$TIDDLER_TEXT" | grep -qi "api" && HAS_API="true"
    echo "$TIDDLER_TEXT" | grep -qi "http\|GET\|POST\|PUT\|DELETE" && HAS_HTTP="true"
fi

# Check tags
HAS_TECHNOLOGY_TAG="false"
HAS_API_TAG="false"

if [ -n "$TIDDLER_TAGS" ]; then
    echo "$TIDDLER_TAGS" | grep -qi "technology" && HAS_TECHNOLOGY_TAG="true"
    echo "$TIDDLER_TAGS" | grep -qi "api" && HAS_API_TAG="true"
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    # Server logs "Dispatching 'save' task:" when saves come through the web UI
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        # Check if any save event matches our expected title (case-insensitive)
        if grep -i "Dispatching 'save' task:.*restful\|Dispatching 'save' task:.*api.*design.*guide" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

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
    "has_agile_link": $HAS_AGILE_LINK,
    "has_vcs_link": $HAS_VCS_LINK,
    "has_any_link": $HAS_ANY_LINK,
    "link_count": $LINK_COUNT,
    "has_rest_keyword": $HAS_REST,
    "has_api_keyword": $HAS_API,
    "has_http_keyword": $HAS_HTTP,
    "has_technology_tag": $HAS_TECHNOLOGY_TAG,
    "has_api_tag": $HAS_API_TAG,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/create_links_result.json"

echo "Result saved to /tmp/create_links_result.json"
cat /tmp/create_links_result.json
echo "=== Export complete ==="
