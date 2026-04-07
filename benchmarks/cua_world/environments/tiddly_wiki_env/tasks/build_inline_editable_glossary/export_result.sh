#!/bin/bash
echo "=== Exporting build_inline_editable_glossary result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/glossary_final.png ga

TIDDLER_DIR="/home/ga/mywiki/tiddlers"
DASHBOARD_TITLE="Glossary Dashboard"
DASHBOARD_EXISTS="false"
DASHBOARD_CONTENT=""

# Check if dashboard exists
if [ "$(tiddler_exists "$DASHBOARD_TITLE")" = "true" ]; then
    DASHBOARD_EXISTS="true"
    DASHBOARD_CONTENT=$(get_tiddler_text "$DASHBOARD_TITLE")
fi

# Check Atelectasis
ATELECTASIS_ES=$(get_tiddler_field "Atelectasis" "es")
ATELECTASIS_MTIME=$(stat -c %Y "$TIDDLER_DIR/Atelectasis.tid" 2>/dev/null || echo "0")
INITIAL_ATEL_MTIME=$(cat /tmp/atelectasis_mtime 2>/dev/null || echo "0")

# Check Tachycardia
TACHYCARDIA_FR=$(get_tiddler_field "Tachycardia" "fr")
TACHY_MTIME=$(stat -c %Y "$TIDDLER_DIR/Tachycardia.tid" 2>/dev/null || echo "0")
INITIAL_TACHY_MTIME=$(cat /tmp/tachycardia_mtime 2>/dev/null || echo "0")

# Check syntax in dashboard
HAS_LIST="false"
HAS_EDIT_TEXT="false"
HAS_TAG_INPUT="false"
HAS_FIELD_ES="false"
HAS_FIELD_FR="false"
HAS_TABLE="false"

if [ -n "$DASHBOARD_CONTENT" ]; then
    echo "$DASHBOARD_CONTENT" | grep -qi "<\$list" && HAS_LIST="true"
    echo "$DASHBOARD_CONTENT" | grep -qi "<\$edit-text" && HAS_EDIT_TEXT="true"
    echo "$DASHBOARD_CONTENT" | grep -qiE "tag=['\"]?input['\"]?" && HAS_TAG_INPUT="true"
    echo "$DASHBOARD_CONTENT" | grep -qiE "field=['\"]?es['\"]?" && HAS_FIELD_ES="true"
    echo "$DASHBOARD_CONTENT" | grep -qiE "field=['\"]?fr['\"]?" && HAS_FIELD_FR="true"
    echo "$DASHBOARD_CONTENT" | grep -qi "<table" && HAS_TABLE="true"
fi

# Check GUI saves
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*atelectasis" /home/ga/tiddlywiki.log 2>/dev/null || \
       grep -qi "Dispatching 'save' task:.*tachycardia" /home/ga/tiddlywiki.log 2>/dev/null || \
       grep -qi "Dispatching 'save' task:.*glossary.*dashboard" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build JSON safely
ESCAPED_DASHBOARD=$(json_escape "$DASHBOARD_CONTENT")
ATELECTASIS_MODIFIED="false"
if [ "$ATELECTASIS_MTIME" != "0" ] && [ "$ATELECTASIS_MTIME" != "$INITIAL_ATEL_MTIME" ]; then
    ATELECTASIS_MODIFIED="true"
fi

TACHYCARDIA_MODIFIED="false"
if [ "$TACHY_MTIME" != "0" ] && [ "$TACHY_MTIME" != "$INITIAL_TACHY_MTIME" ]; then
    TACHYCARDIA_MODIFIED="true"
fi

JSON_RESULT=$(cat << EOF
{
    "dashboard_exists": $DASHBOARD_EXISTS,
    "dashboard_content": "$ESCAPED_DASHBOARD",
    "has_list": $HAS_LIST,
    "has_edit_text": $HAS_EDIT_TEXT,
    "has_tag_input": $HAS_TAG_INPUT,
    "has_field_es": $HAS_FIELD_ES,
    "has_field_fr": $HAS_FIELD_FR,
    "has_table": $HAS_TABLE,
    "atelectasis_es": "$(json_escape "$ATELECTASIS_ES")",
    "atelectasis_modified": $ATELECTASIS_MODIFIED,
    "tachycardia_fr": "$(json_escape "$TACHYCARDIA_FR")",
    "tachycardia_modified": $TACHYCARDIA_MODIFIED,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/glossary_result.json"
echo "Result saved to /tmp/glossary_result.json"
cat /tmp/glossary_result.json
echo "=== Export complete ==="