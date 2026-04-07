#!/bin/bash
echo "=== Exporting create_tabbed_project_page result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/tabbed_page_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to check creation time
check_created_during_task() {
    local title="$1"
    local sanitized=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
    local file="$TIDDLER_DIR/${sanitized}.tid"
    if [ ! -f "$file" ]; then
        file=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
    fi
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "true"
            return 0
        fi
    fi
    echo "false"
}

# 1. Main Tiddler
MAIN_TITLE="CRISPR-Cas9 Project Overview"
MAIN_EXISTS=$(tiddler_exists "$MAIN_TITLE")
MAIN_TEXT=""
MAIN_HAS_MACRO="false"
MAIN_HAS_DEFAULT="false"

if [ "$MAIN_EXISTS" = "true" ]; then
    MAIN_TEXT=$(get_tiddler_text "$MAIN_TITLE")
    if echo "$MAIN_TEXT" | grep -qi "<<tabs"; then
        if echo "$MAIN_TEXT" | grep -qi "CRISPR-Cas9 Tabs"; then
            MAIN_HAS_MACRO="true"
        fi
        if echo "$MAIN_TEXT" | grep -qi "CRISPR-Cas9 Protocol"; then
            MAIN_HAS_DEFAULT="true"
        fi
    fi
fi

# 2. Protocol Tab
PROTOCOL_TITLE="CRISPR-Cas9 Protocol"
PROTOCOL_EXISTS=$(tiddler_exists "$PROTOCOL_TITLE")
PROTOCOL_TAGS=""
PROTOCOL_CAPTION=""
PROTOCOL_TEXT=""
PROTOCOL_CREATED=$(check_created_during_task "$PROTOCOL_TITLE")

if [ "$PROTOCOL_EXISTS" = "true" ]; then
    PROTOCOL_TAGS=$(get_tiddler_field "$PROTOCOL_TITLE" "tags")
    PROTOCOL_CAPTION=$(get_tiddler_field "$PROTOCOL_TITLE" "caption")
    PROTOCOL_TEXT=$(get_tiddler_text "$PROTOCOL_TITLE")
fi

# 3. Equipment Tab
EQUIPMENT_TITLE="CRISPR-Cas9 Equipment"
EQUIPMENT_EXISTS=$(tiddler_exists "$EQUIPMENT_TITLE")
EQUIPMENT_TAGS=""
EQUIPMENT_CAPTION=""
EQUIPMENT_TEXT=""
EQUIPMENT_CREATED=$(check_created_during_task "$EQUIPMENT_TITLE")

if [ "$EQUIPMENT_EXISTS" = "true" ]; then
    EQUIPMENT_TAGS=$(get_tiddler_field "$EQUIPMENT_TITLE" "tags")
    EQUIPMENT_CAPTION=$(get_tiddler_field "$EQUIPMENT_TITLE" "caption")
    EQUIPMENT_TEXT=$(get_tiddler_text "$EQUIPMENT_TITLE")
fi

# 4. Results Tab
RESULTS_TITLE="CRISPR-Cas9 Results"
RESULTS_EXISTS=$(tiddler_exists "$RESULTS_TITLE")
RESULTS_TAGS=""
RESULTS_CAPTION=""
RESULTS_TEXT=""
RESULTS_CREATED=$(check_created_during_task "$RESULTS_TITLE")

if [ "$RESULTS_EXISTS" = "true" ]; then
    RESULTS_TAGS=$(get_tiddler_field "$RESULTS_TITLE" "tags")
    RESULTS_CAPTION=$(get_tiddler_field "$RESULTS_TITLE" "caption")
    RESULTS_TEXT=$(get_tiddler_text "$RESULTS_TITLE")
fi

# 5. References Tab
REFS_TITLE="CRISPR-Cas9 References"
REFS_EXISTS=$(tiddler_exists "$REFS_TITLE")
REFS_TAGS=""
REFS_CAPTION=""
REFS_TEXT=""
REFS_CREATED=$(check_created_during_task "$REFS_TITLE")

if [ "$REFS_EXISTS" = "true" ]; then
    REFS_TAGS=$(get_tiddler_field "$REFS_TITLE" "tags")
    REFS_CAPTION=$(get_tiddler_field "$REFS_TITLE" "caption")
    REFS_TEXT=$(get_tiddler_text "$REFS_TITLE")
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*CRISPR" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Construct JSON Output safely using escaping
JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "main": {
        "exists": $MAIN_EXISTS,
        "text": "$(json_escape "$MAIN_TEXT")",
        "has_macro": $MAIN_HAS_MACRO,
        "has_default": $MAIN_HAS_DEFAULT
    },
    "protocol": {
        "exists": $PROTOCOL_EXISTS,
        "created_during_task": $PROTOCOL_CREATED,
        "tags": "$(json_escape "$PROTOCOL_TAGS")",
        "caption": "$(json_escape "$PROTOCOL_CAPTION")",
        "text": "$(json_escape "$PROTOCOL_TEXT")"
    },
    "equipment": {
        "exists": $EQUIPMENT_EXISTS,
        "created_during_task": $EQUIPMENT_CREATED,
        "tags": "$(json_escape "$EQUIPMENT_TAGS")",
        "caption": "$(json_escape "$EQUIPMENT_CAPTION")",
        "text": "$(json_escape "$EQUIPMENT_TEXT")"
    },
    "results": {
        "exists": $RESULTS_EXISTS,
        "created_during_task": $RESULTS_CREATED,
        "tags": "$(json_escape "$RESULTS_TAGS")",
        "caption": "$(json_escape "$RESULTS_CAPTION")",
        "text": "$(json_escape "$RESULTS_TEXT")"
    },
    "references": {
        "exists": $REFS_EXISTS,
        "created_during_task": $REFS_CREATED,
        "tags": "$(json_escape "$REFS_TAGS")",
        "caption": "$(json_escape "$REFS_CAPTION")",
        "text": "$(json_escape "$REFS_TEXT")"
    },
    "gui_save_detected": $GUI_SAVE_DETECTED
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/tabbed_page_result.json"

echo "Result saved to /tmp/tabbed_page_result.json"
echo "=== Export complete ==="