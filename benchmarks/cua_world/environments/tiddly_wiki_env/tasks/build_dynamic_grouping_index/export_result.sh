#!/bin/bash
echo "=== Exporting result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Find the tiddler file robustly
TIDDLER_FILE=$(grep -l "^title: Director Index" /home/ga/mywiki/tiddlers/*.tid 2>/dev/null | head -1)

if [ -z "$TIDDLER_FILE" ]; then
    # Try case-insensitive or underscore variations
    TIDDLER_FILE=$(grep -il "^title:.*director.*index" /home/ga/mywiki/tiddlers/*.tid 2>/dev/null | head -1)
fi

TIDDLER_EXISTS="false"
TIDDLER_MTIME=0
TIDDLER_CONTENT=""
TAGS=""
RENDERED_HTML=""

if [ -n "$TIDDLER_FILE" ]; then
    TIDDLER_EXISTS="true"
    TIDDLER_MTIME=$(stat -c %Y "$TIDDLER_FILE" 2>/dev/null || echo "0")
    
    ACTUAL_TITLE=$(grep -i "^title:" "$TIDDLER_FILE" | head -1 | sed 's/^title: *//' | tr -d '\r')
    TAGS=$(grep -i "^tags:" "$TIDDLER_FILE" | head -1 | sed 's/^tags: *//' | tr -d '\r')
    TIDDLER_CONTENT=$(awk '/^$/{found=1; next} found{print}' "$TIDDLER_FILE")
    
    # Render the dynamic node into static HTML to assess the data output reliably
    echo "Rendering HTML for '$ACTUAL_TITLE'..."
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render '$ACTUAL_TITLE' 'output.html' 'text/html' '\$:/core/templates/tiddler-body'"
    if [ -f /home/ga/mywiki/output/output.html ]; then
        RENDERED_HTML=$(cat /home/ga/mywiki/output/output.html)
    fi
fi

# Package all data to cross the env boundary
ESCAPED_TEXT=$(json_escape "$TIDDLER_CONTENT")
ESCAPED_HTML=$(json_escape "$RENDERED_HTML")
ESCAPED_TAGS=$(json_escape "$TAGS")

JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_mtime": $TIDDLER_MTIME,
    "raw_text": "$ESCAPED_TEXT",
    "rendered_html": "$ESCAPED_HTML",
    "tags": "$ESCAPED_TAGS",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="