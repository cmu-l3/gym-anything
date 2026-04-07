#!/bin/bash
echo "=== Exporting create_data_entry_form result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

TIDDLER_TITLE="Bird Sighting Entry Form"
TIDDLER_EXISTS=$(tiddler_exists "$TIDDLER_TITLE")
TIDDLER_TEXT=""
TIDDLER_TEXT_B64=""

if [ "$TIDDLER_EXISTS" = "true" ]; then
    TIDDLER_TEXT=$(get_tiddler_text "$TIDDLER_TITLE")
    # Base64 encode to safely pass raw WikiText containing quotes/newlines via JSON
    TIDDLER_TEXT_B64=$(echo -n "$TIDDLER_TEXT" | base64 -w 0)
fi

INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*bird.*sighting.*entry.*form" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_text_b64": "$TIDDLER_TEXT_B64",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="