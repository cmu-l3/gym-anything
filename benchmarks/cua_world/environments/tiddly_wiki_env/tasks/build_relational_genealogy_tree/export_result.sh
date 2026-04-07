#!/bin/bash
echo "=== Exporting build_relational_genealogy_tree result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/genealogy_final.png

# Array of expected historical persons
declare -A PERSONS=(
    ["Queen Victoria"]="Queen Victoria"
    ["Prince Albert"]="Prince Albert"
    ["Victoria, Princess Royal"]="Victoria, Princess Royal"
    ["Edward VII"]="Edward VII"
    ["Princess Alice"]="Princess Alice"
)

JSON_PERSONS="{}"

for p in "${!PERSONS[@]}"; do
    EXISTS=$(tiddler_exists "$p")
    TAGS=$(get_tiddler_field "$p" "tags")
    DOB=$(get_tiddler_field "$p" "birth-date")
    MOTHER=$(get_tiddler_field "$p" "mother")
    FATHER=$(get_tiddler_field "$p" "father")

    HAS_PERSON_TAG="false"
    echo "$TAGS" | grep -qi "Person" && HAS_PERSON_TAG="true"

    # Construct JSON for this person
    P_JSON="\"exists\": $EXISTS, \"has_person_tag\": $HAS_PERSON_TAG, \"dob\": \"$(json_escape "$DOB")\", \"mother\": \"$(json_escape "$MOTHER")\", \"father\": \"$(json_escape "$FATHER")\""
    
    if [ "$JSON_PERSONS" = "{}" ]; then
        JSON_PERSONS="\"$p\": {$P_JSON}"
    else
        JSON_PERSONS="$JSON_PERSONS, \"$p\": {$P_JSON}"
    fi
done

# Find the ViewTemplate tiddler
TEMPLATE_TITLE=""
TEMPLATE_TEXT=""
TEMPLATE_TAGS=""
while IFS= read -r f; do
    if grep -qi "tags:.*\$:/tags/ViewTemplate" "$f"; then
        TEMPLATE_TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
        TEMPLATE_TAGS=$(grep "^tags:" "$f" | head -1 | sed 's/^tags: *//')
        TEMPLATE_TEXT=$(awk '/^$/{found=1; next} found{print}' "$f")
        break
    fi
done < <(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" 2>/dev/null)

ESCAPED_TEMPLATE_TITLE=$(json_escape "$TEMPLATE_TITLE")
ESCAPED_TEMPLATE_TEXT=$(json_escape "$TEMPLATE_TEXT")
ESCAPED_TEMPLATE_TAGS=$(json_escape "$TEMPLATE_TAGS")

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qiE "Dispatching 'save' task:.*victoria|Dispatching 'save' task:.*albert|Dispatching 'save' task:.*edward|Dispatching 'save' task:.*alice|Dispatching 'save' task:.*template" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build JSON result
JSON_RESULT=$(cat << EOF
{
    "persons": {$JSON_PERSONS},
    "template_found": $([ -n "$TEMPLATE_TITLE" ] && echo "true" || echo "false"),
    "template_title": "$ESCAPED_TEMPLATE_TITLE",
    "template_tags": "$ESCAPED_TEMPLATE_TAGS",
    "template_text": "$ESCAPED_TEMPLATE_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/genealogy_result.json"

echo "Result saved to /tmp/genealogy_result.json"
cat /tmp/genealogy_result.json
echo "=== Export complete ==="