#!/bin/bash
echo "=== Exporting DJ Setlist Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TIDDLER_TITLE="Smith Wedding Setlist"

TIDDLER_EXISTS=$(tiddler_exists "$TIDDLER_TITLE")
TIDDLER_TEXT=""
RENDERED_HTML=""

if [ "$TIDDLER_EXISTS" = "true" ]; then
    TIDDLER_TEXT=$(get_tiddler_text "$TIDDLER_TITLE")
    
    # Render it to HTML to check the filter results natively
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render '$TIDDLER_TITLE' 'setlist.html' 'text/html' '\$:/core/templates/tiddler-body'"
    
    if [ -f "/home/ga/mywiki/output/setlist.html" ]; then
        RENDERED_HTML=$(cat /home/ga/mywiki/output/setlist.html)
    fi
fi

# Also check server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*smith.*wedding" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")
ESCAPED_HTML=$(json_escape "$RENDERED_HTML")

JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_text": "$ESCAPED_TEXT",
    "rendered_html": "$ESCAPED_HTML",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/dj_setlist_result.json"

echo "Result saved to /tmp/dj_setlist_result.json"
echo "=== Export complete ==="