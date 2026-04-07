#!/bin/bash
echo "=== Exporting build_interactive_transit_explorer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/transit_final.png

TARGET_TITLE="CTA Line Explorer"
TIDDLER_EXISTS="false"
TIDDLER_TEXT=""

# Extract the created tiddler
if [ "$(tiddler_exists "$TARGET_TITLE")" = "true" ]; then
    TIDDLER_EXISTS="true"
    TIDDLER_TEXT=$(get_tiddler_text "$TARGET_TITLE")
fi

# Check TiddlyWiki server log for GUI save events (Anti-gaming check)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*cta.*line.*explorer" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

# Clean output for JSON packing
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")

JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_text": "$ESCAPED_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/transit_explorer_result.json"

echo "Result saved to /tmp/transit_explorer_result.json"
cat /tmp/transit_explorer_result.json
echo "=== Export complete ==="