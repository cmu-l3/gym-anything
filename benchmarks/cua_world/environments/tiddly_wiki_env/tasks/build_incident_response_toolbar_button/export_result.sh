#!/bin/bash
echo "=== Exporting build_incident_response_toolbar_button result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

TEMPLATE_TITLE="Incident Template"
BUTTON_TITLE='$:/custom/buttons/NewIncident'

# 1. Retrieve Template Information
TEMPLATE_EXISTS=$(tiddler_exists "$TEMPLATE_TITLE")
TEMPLATE_TAGS=""
TEMPLATE_STATUS=""
TEMPLATE_SEVERITY=""
TEMPLATE_TEXT=""
TEMPLATE_MTIME=0

if [ "$TEMPLATE_EXISTS" = "true" ]; then
    TEMPLATE_TAGS=$(get_tiddler_field "$TEMPLATE_TITLE" "tags")
    TEMPLATE_STATUS=$(get_tiddler_field "$TEMPLATE_TITLE" "status")
    TEMPLATE_SEVERITY=$(get_tiddler_field "$TEMPLATE_TITLE" "severity")
    TEMPLATE_TEXT=$(get_tiddler_text "$TEMPLATE_TITLE")
    
    # Try to get modification time of the file
    sanitized=$(echo "$TEMPLATE_TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
    file_path=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        TEMPLATE_MTIME=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
    fi
fi

# 2. Retrieve Button Information
BUTTON_EXISTS=$(tiddler_exists "$BUTTON_TITLE")
BUTTON_TAGS=""
BUTTON_CAPTION=""
BUTTON_DESC=""
BUTTON_TEXT=""
BUTTON_MTIME=0

if [ "$BUTTON_EXISTS" = "true" ]; then
    BUTTON_TAGS=$(get_tiddler_field "$BUTTON_TITLE" "tags")
    BUTTON_CAPTION=$(get_tiddler_field "$BUTTON_TITLE" "caption")
    BUTTON_DESC=$(get_tiddler_field "$BUTTON_TITLE" "description")
    BUTTON_TEXT=$(get_tiddler_text "$BUTTON_TITLE")
    
    sanitized=$(echo "$BUTTON_TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
    file_path=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        BUTTON_MTIME=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
    fi
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*incident.*template\|Dispatching 'save' task:.*custom/buttons" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape JSON payload properties
ESC_TEMPLATE_TAGS=$(json_escape "$TEMPLATE_TAGS")
ESC_TEMPLATE_STATUS=$(json_escape "$TEMPLATE_STATUS")
ESC_TEMPLATE_SEVERITY=$(json_escape "$TEMPLATE_SEVERITY")
ESC_TEMPLATE_TEXT=$(json_escape "$TEMPLATE_TEXT")

ESC_BUTTON_TAGS=$(json_escape "$BUTTON_TAGS")
ESC_BUTTON_CAPTION=$(json_escape "$BUTTON_CAPTION")
ESC_BUTTON_DESC=$(json_escape "$BUTTON_DESC")
ESC_BUTTON_TEXT=$(json_escape "$BUTTON_TEXT")

JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    
    "template_exists": $TEMPLATE_EXISTS,
    "template_mtime": $TEMPLATE_MTIME,
    "template_tags": "$ESC_TEMPLATE_TAGS",
    "template_status": "$ESC_TEMPLATE_STATUS",
    "template_severity": "$ESC_TEMPLATE_SEVERITY",
    "template_text": "$ESC_TEMPLATE_TEXT",
    
    "button_exists": $BUTTON_EXISTS,
    "button_mtime": $BUTTON_MTIME,
    "button_tags": "$ESC_BUTTON_TAGS",
    "button_caption": "$ESC_BUTTON_CAPTION",
    "button_desc": "$ESC_BUTTON_DESC",
    "button_text": "$ESC_BUTTON_TEXT",
    
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="