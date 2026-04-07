#!/bin/bash
echo "=== Exporting delete_deprecated_tiddlers result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Initialize variables
DEPRECATED_TITLES=(
    "PCR Protocol v1"
    "Supplier List 2022"
    "Old Lab Safety Rules"
    "Western Blot Protocol v2"
    "Budget Proposal Q1 2023"
)

PRESERVED_TITLES=(
    "PCR Protocol v3"
    "Western Blot Protocol v4"
    "Lab Meeting Notes 2024-01-15"
    "Current Supplier List"
    "Lab Safety Guidelines 2024"
    "Equipment Inventory"
    "Research Project Alpha"
    "Graduate Student Onboarding"
)

DEPRECATED_REMAINING=()
PRESERVED_REMAINING=()

# Check deprecated tiddlers
for title in "${DEPRECATED_TITLES[@]}"; do
    if [ "$(tiddler_exists "$title")" = "true" ]; then
        DEPRECATED_REMAINING+=("$title")
    fi
done

# Check preserved tiddlers
for title in "${PRESERVED_TITLES[@]}"; do
    if [ "$(tiddler_exists "$title")" = "true" ]; then
        PRESERVED_REMAINING+=("$title")
    fi
done

# Format bash arrays to JSON arrays
printf -v DEP_JSON ',"%s"' "${DEPRECATED_REMAINING[@]}"
DEP_JSON="[${DEP_JSON:1}]"
if [ "$DEP_JSON" = "[]" ]; then DEP_JSON="[]"; fi

printf -v PRES_JSON ',"%s"' "${PRESERVED_REMAINING[@]}"
PRES_JSON="[${PRES_JSON:1}]"
if [ "$PRES_JSON" = "[]" ]; then PRES_JSON="[]"; fi

CURRENT_COUNT=$(count_user_tiddlers)
INITIAL_COUNT=$(wc -l < /tmp/initial_tiddlers.txt 2>/dev/null || echo "13")

# Check TiddlyWiki server log for GUI delete events (anti-gaming)
GUI_DELETE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'delete' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_DELETE_DETECTED="true"
    fi
fi

# Check if wiki is still functional
WIKI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/" 2>/dev/null || echo "000")
WIKI_FUNCTIONAL="false"
if [ "$WIKI_STATUS" = "200" ]; then
    WIKI_FUNCTIONAL="true"
fi

JSON_RESULT=$(cat << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "deprecated_remaining": $DEP_JSON,
    "preserved_remaining": $PRES_JSON,
    "gui_delete_detected": $GUI_DELETE_DETECTED,
    "wiki_functional": $WIKI_FUNCTIONAL,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="