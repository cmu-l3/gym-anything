#!/bin/bash
echo "=== Exporting build_historical_cyoa_narrative result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/cyoa_final.png

# Function to safely extract tiddler text and properties into JSON object
get_tiddler_json() {
    local title="$1"
    if [ "$(tiddler_exists "$title")" = "true" ]; then
        local tags=$(get_tiddler_field "$title" "tags")
        local text=$(get_tiddler_text "$title")
        echo "{\"exists\": true, \"tags\": \"$(json_escape "$tags")\", \"text\": \"$(json_escape "$text")\"}"
    else
        echo "{\"exists\": false, \"tags\": \"\", \"text\": \"\"}"
    fi
}

# Extract specific story nodes
NODE_ENDURANCE=$(get_tiddler_json "Endurance Expedition")
NODE_CRUSHED=$(get_tiddler_json "Ship Crushed")
NODE_OCEAN=$(get_tiddler_json "Ocean Camp")
NODE_MARCH=$(get_tiddler_json "Paulet Island March")
NODE_PATIENCE=$(get_tiddler_json "Patience Camp")

# Extract DefaultTiddlers configuration
DEFAULT_TIDDLERS_TEXT=""
if [ -f "$TIDDLER_DIR/\$__DefaultTiddlers.tid" ]; then
    DEFAULT_TIDDLERS_TEXT=$(awk '/^$/{found=1; next} found{print}' "$TIDDLER_DIR/\$__DefaultTiddlers.tid")
elif [ -f "$TIDDLER_DIR/DefaultTiddlers.tid" ]; then
    # Fallback in case of weird naming
    DEFAULT_TIDDLERS_TEXT=$(awk '/^$/{found=1; next} found{print}' "$TIDDLER_DIR/DefaultTiddlers.tid")
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Compile JSON result
JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "default_tiddlers": "$(json_escape "$DEFAULT_TIDDLERS_TEXT")",
    "node_endurance": $NODE_ENDURANCE,
    "node_crushed": $NODE_CRUSHED,
    "node_ocean": $NODE_OCEAN,
    "node_march": $NODE_MARCH,
    "node_patience": $NODE_PATIENCE,
    "screenshot_path": "/tmp/cyoa_final.png"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/cyoa_result.json"

echo "Result saved to /tmp/cyoa_result.json"
echo "=== Export complete ==="