#!/bin/bash
echo "=== Exporting build_faceted_exoplanet_catalog result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target tiddler name
TARGET="Exoplanet Explorer"
TIDDLER_EXISTS="false"
TIDDLER_TEXT=""
TIDDLER_MTIME=0
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if target tiddler exists
if [ "$(tiddler_exists "$TARGET")" = "true" ]; then
    TIDDLER_EXISTS="true"
    TIDDLER_TEXT=$(get_tiddler_content "$TARGET")
    
    # Get file modification time
    sanitized=$(echo "$TARGET" | sed 's/[\/\\:*?"<>|]/_/g')
    file_path=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
    if [ -f "$file_path" ]; then
        TIDDLER_MTIME=$(stat -c %Y "$file_path")
    fi
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*exoplanet.*explorer" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

# Escape content for JSON safely
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")

# Build JSON result
JSON_RESULT=$(cat << EOF
{
    "task_start_time": $TASK_START_TIME,
    "tiddler_mtime": $TIDDLER_MTIME,
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_content": "$ESCAPED_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="