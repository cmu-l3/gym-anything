#!/bin/bash
echo "=== Exporting create_dynamic_invoice_table result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Render the tiddler using TiddlyWiki CLI to test dynamic output
echo "Rendering dashboard tiddler to HTML..."
rm -rf /home/ga/mywiki/output 2>/dev/null || true
su - ga -c "cd /home/ga/mywiki && tiddlywiki --render 'Invoice Dashboard' 'dashboard.html' 'text/plain' '\$:/core/templates/tiddler-body'" > /tmp/tw_render.log 2>&1

RENDERED_HTML=""
if [ -f "/home/ga/mywiki/output/dashboard.html" ]; then
    RENDERED_HTML=$(cat "/home/ga/mywiki/output/dashboard.html")
    echo "Successfully rendered dashboard."
else
    echo "Failed to render dashboard or tiddler does not exist."
fi

# 3. Extract raw file content and metadata
EXPECTED_TITLE="Invoice Dashboard"
TIDDLER_FOUND="false"
TIDDLER_TAGS=""
TIDDLER_TEXT=""
FILE_MODIFIED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    TIDDLER_FOUND="true"
    TIDDLER_TAGS=$(get_tiddler_field "$EXPECTED_TITLE" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
    
    # Check creation/modification time
    SANITIZED_TITLE=$(echo "$EXPECTED_TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
    FILE_PATH="$TIDDLER_DIR/${SANITIZED_TITLE}.tid"
    if [ ! -f "$FILE_PATH" ]; then
        FILE_PATH=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${SANITIZED_TITLE}.tid" 2>/dev/null | head -1)
    fi
    
    if [ -f "$FILE_PATH" ]; then
        FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILE_MODIFIED_DURING_TASK="true"
        fi
    fi
fi

# 4. Check GUI interaction (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*invoice.*dashboard" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# 5. Pack everything into JSON
ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")
ESCAPED_HTML=$(json_escape "$RENDERED_HTML")

JSON_RESULT=$(cat << EOF
{
    "tiddler_found": $TIDDLER_FOUND,
    "tiddler_tags": "$ESCAPED_TAGS",
    "raw_text": "$ESCAPED_TEXT",
    "rendered_html": "$ESCAPED_HTML",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="