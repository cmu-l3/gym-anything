#!/bin/bash
echo "=== Exporting create_dictionary_tiddler_relational_data result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/relational_data_final.png

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

# Retrieve raw content of the expected tiddlers
CONTENT_OPS=$(get_tiddler_content "Root-Operators")
CONTENT_V4=$(get_tiddler_content "Root-IPv4")
CONTENT_V6=$(get_tiddler_content "Root-IPv6")
CONTENT_TABLE=$(get_tiddler_content "DNS Root Servers Table")

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*Root-IPv4\|Dispatching 'save' task:.*DNS Root Servers Table" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape content for JSON safely using the utility function
ESCAPED_OPS=$(json_escape "$CONTENT_OPS")
ESCAPED_V4=$(json_escape "$CONTENT_V4")
ESCAPED_V6=$(json_escape "$CONTENT_V6")
ESCAPED_TABLE=$(json_escape "$CONTENT_TABLE")

JSON_RESULT=$(cat << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "tiddler_ops_raw": "$ESCAPED_OPS",
    "tiddler_v4_raw": "$ESCAPED_V4",
    "tiddler_v6_raw": "$ESCAPED_V6",
    "tiddler_table_raw": "$ESCAPED_TABLE",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/relational_data_result.json"

echo "Result saved to /tmp/relational_data_result.json"
echo "=== Export complete ==="