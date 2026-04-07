#!/bin/bash
echo "=== Exporting create_crm_dashboard_aggregations result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing what the agent saw
take_screenshot /tmp/task_final.png

TARGET="CRM Dashboard"
TIDDLER_EXISTS=$(tiddler_exists "$TARGET")
TIDDLER_TAGS=""
RAW_TEXT=""
HTML_RENDER=""
MUTATION_SUCCESS="false"

if [ "$TIDDLER_EXISTS" = "true" ]; then
    echo "Dashboard tiddler found. Extracting data and performing mutation test..."
    RAW_TEXT=$(get_tiddler_text "$TARGET")
    TIDDLER_TAGS=$(get_tiddler_field "$TARGET" "tags")
    
    # 1. Mutate the underlying client data
    # Change TechCorp's revenue from 100000 to 500000
    # This increases Active sum by 400,000 (900k -> 1.3m) and sets new max Active to 500k.
    TECHCORP_FILE="/home/ga/mywiki/tiddlers/TechCorp.tid"
    if [ -f "$TECHCORP_FILE" ]; then
        sed -i 's/revenue: 100000/revenue: 500000/' "$TECHCORP_FILE"
        MUTATION_SUCCESS="true"
        echo "Mutated TechCorp data for anti-gaming test."
    fi
    
    # Wait for node.js to register file change internally
    sleep 3
    
    # 2. Render the tiddler to HTML via CLI to capture the dynamically evaluated math
    echo "Rendering dashboard to static HTML..."
    rm -rf /home/ga/mywiki/output 2>/dev/null || true
    su - ga -c "cd /home/ga && tiddlywiki mywiki --render '$TARGET' 'dashboard.html' 'text/html'"
    
    HTML_OUTPUT_FILE="/home/ga/mywiki/output/dashboard.html"
    if [ -f "$HTML_OUTPUT_FILE" ]; then
        HTML_RENDER=$(cat "$HTML_OUTPUT_FILE")
    else
        echo "WARNING: Failed to render HTML output."
    fi
    
    # Revert mutation just in case
    if [ -f "$TECHCORP_FILE" ]; then
        sed -i 's/revenue: 500000/revenue: 100000/' "$TECHCORP_FILE"
    fi
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*crm.*dashboard" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

# Escape text for JSON packaging
ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")
ESCAPED_TEXT=$(json_escape "$RAW_TEXT")
ESCAPED_HTML=$(json_escape "$HTML_RENDER")

JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_tags": "$ESCAPED_TAGS",
    "raw_text": "$ESCAPED_TEXT",
    "rendered_html_after_mutation": "$ESCAPED_HTML",
    "mutation_success": $MUTATION_SUCCESS,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="