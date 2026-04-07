#!/bin/bash
echo "=== Exporting import_json_data_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/import_final.png

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

# Check how many earthquake tiddlers exist
EARTHQUAKE_COUNT=0
for target in "1960 Valdivia earthquake" "1964 Alaska earthquake" "2004 Indian Ocean earthquake" "2011 Tohoku earthquake" "1952 Kamchatka earthquake" "2010 Chile earthquake" "1906 Ecuador-Colombia earthquake" "1965 Rat Islands earthquake" "1950 Assam-Tibet earthquake" "2012 Indian Ocean earthquake"; do
    if [ "$(tiddler_exists "$target")" = "true" ]; then
        EARTHQUAKE_COUNT=$((EARTHQUAKE_COUNT + 1))
    fi
done

# Search for the dashboard tiddler
EXPECTED_TITLE="Top Earthquakes Dashboard"
DASHBOARD_FOUND="false"
DASHBOARD_TAGS=""
DASHBOARD_TEXT=""

if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    DASHBOARD_FOUND="true"
    DASHBOARD_TAGS=$(get_tiddler_field "$EXPECTED_TITLE" "tags")
    DASHBOARD_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
fi

# Try partial match if exact not found
if [ "$DASHBOARD_FOUND" = "false" ]; then
    MATCH_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -newer /tmp/initial_tiddler_count 2>/dev/null | while IFS= read -r f; do
        TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
        if echo "$TITLE" | grep -qi "top.*earthquake\|earthquake.*dashboard"; then
            echo "$f"
            break
        fi
    done)

    if [ -n "$MATCH_FILE" ]; then
        DASHBOARD_FOUND="true"
        DASHBOARD_TAGS=$(grep "^tags:" "$MATCH_FILE" | head -1 | sed 's/^tags: *//')
        DASHBOARD_TEXT=$(awk '/^$/{found=1; next} found{print}' "$MATCH_FILE")
    fi
fi

# Check for Dashboard tag
HAS_DASHBOARD_TAG="false"
if [ -n "$DASHBOARD_TAGS" ]; then
    echo "$DASHBOARD_TAGS" | grep -qi "dashboard" && HAS_DASHBOARD_TAG="true"
fi

# Check filter syntax in text
HAS_TAG_FILTER="false"
HAS_SORT_FILTER="false"
HAS_LIMIT_FILTER="false"

if [ -n "$DASHBOARD_TEXT" ]; then
    echo "$DASHBOARD_TEXT" | grep -Fq "tag[Earthquake]" && HAS_TAG_FILTER="true"
    echo "$DASHBOARD_TEXT" | grep -Fq "!nsort[magnitude]" && HAS_SORT_FILTER="true"
    echo "$DASHBOARD_TEXT" | grep -Fq "limit[5]" && HAS_LIMIT_FILTER="true"
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*earthquake.*dashboard" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
    # Also detect the bulk import saving the earthquake tiddlers
    if grep -qi "Dispatching 'save' task:.*1960 Valdivia" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build JSON result
ESCAPED_TAGS=$(json_escape "$DASHBOARD_TAGS")
ESCAPED_TEXT=$(json_escape "$DASHBOARD_TEXT")

JSON_RESULT=$(cat << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "earthquakes_imported": $EARTHQUAKE_COUNT,
    "dashboard_found": $DASHBOARD_FOUND,
    "dashboard_tags": "$ESCAPED_TAGS",
    "dashboard_text": "$ESCAPED_TEXT",
    "has_dashboard_tag": $HAS_DASHBOARD_TAG,
    "has_tag_filter": $HAS_TAG_FILTER,
    "has_sort_filter": $HAS_SORT_FILTER,
    "has_limit_filter": $HAS_LIMIT_FILTER,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/import_task_result.json"

echo "Result saved to /tmp/import_task_result.json"
cat /tmp/import_task_result.json
echo "=== Export complete ==="