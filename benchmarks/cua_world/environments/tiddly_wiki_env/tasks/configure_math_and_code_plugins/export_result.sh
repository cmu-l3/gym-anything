#!/bin/bash
echo "=== Exporting configure_math_and_code_plugins result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if TiddlyWiki server was restarted by comparing PIDs
INITIAL_PID=$(cat /tmp/initial_tw_pid 2>/dev/null || echo "0")
CURRENT_PID=$(pgrep -f "tiddlywiki" | head -1 || echo "0")
SERVER_RESTARTED="false"
if [ "$CURRENT_PID" != "0" ] && [ "$CURRENT_PID" != "$INITIAL_PID" ]; then
    SERVER_RESTARTED="true"
fi

# Check tiddlywiki.info configuration using jq
PLUGINS_JSON=$(su - ga -c "jq -c '.plugins // []' /home/ga/mywiki/tiddlywiki.info 2>/dev/null" || echo "[]")
if [ -z "$PLUGINS_JSON" ]; then
    PLUGINS_JSON="[]"
fi

# Target tiddler checks
TARGET="Softmax Function"
TIDDLER_EXISTS=$(tiddler_exists "$TARGET")
TAGS=""
RAW_TEXT=""
HAS_MATH_MARKER="false"
HAS_CODE_MARKER="false"

if [ "$TIDDLER_EXISTS" = "true" ]; then
    TAGS=$(get_tiddler_field "$TARGET" "tags")
    RAW_TEXT=$(get_tiddler_text "$TARGET")
    
    # Safely check for required syntax markers
    echo "$RAW_TEXT" | grep -q '\$\$' && HAS_MATH_MARKER="true"
    echo "$RAW_TEXT" | grep -q '