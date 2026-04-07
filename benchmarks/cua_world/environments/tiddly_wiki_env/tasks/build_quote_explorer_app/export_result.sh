#!/bin/bash
echo "=== Exporting build_quote_explorer_app result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target tiddler
TARGET="Quote Explorer"

TIDDLER_EXISTS=$(tiddler_exists "$TARGET")
TIDDLER_TEXT=""
TIDDLER_MTIME=0

HAS_COUNT_WIDGET="false"
HAS_LIST_WIDGET="false"
HAS_CHECKBOX_WIDGET="false"
HAS_TOTAL_QUOTES_FILTER="false"
HAS_STARRED_QUOTES_FILTER="false"
HAS_UNIQUE_AUTHOR_FILTER="false"
HAS_COMBINED_TAG_FILTER="false"

STARRED_COUNT=0

if [ "$TIDDLER_EXISTS" = "true" ]; then
    # Locate exact file
    SANITIZED=$(echo "$TARGET" | sed 's/[\/\\:*?"<>|]/_/g')
    FILE_PATH=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${SANITIZED}.tid" 2>/dev/null | head -1)
    
    if [ -f "$FILE_PATH" ]; then
        TIDDLER_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        TIDDLER_TEXT=$(get_tiddler_text "$TARGET")
        
        # Check for required widgets
        echo "$TIDDLER_TEXT" | grep -qi "<$count" && HAS_COUNT_WIDGET="true"
        echo "$TIDDLER_TEXT" | grep -qi "<$list" && HAS_LIST_WIDGET="true"
        echo "$TIDDLER_TEXT" | grep -qi "<$checkbox" && HAS_CHECKBOX_WIDGET="true"
        
        # Check for specific filter expressions
        # Total quotes filter: [tag[Quote]]
        echo "$TIDDLER_TEXT" | grep -qi "\[tag\[Quote\]\]" && HAS_TOTAL_QUOTES_FILTER="true"
        
        # Starred quotes filter: [tag[Starred]]
        echo "$TIDDLER_TEXT" | grep -qi "\[tag\[Starred\]\]" && HAS_STARRED_QUOTES_FILTER="true"
        
        # Unique authors filter: get[author]unique[] OR each[author]
        if echo "$TIDDLER_TEXT" | grep -qiE "(get\[author\]|each\[author\])" && echo "$TIDDLER_TEXT" | grep -qiE "(unique\[\]|each\[author\])"; then
            HAS_UNIQUE_AUTHOR_FILTER="true"
        fi
        
        # Combined filter for shortlist: [tag[Quote]tag[Starred]] or [tag[Starred]tag[Quote]]
        if echo "$TIDDLER_TEXT" | grep -qiE "\[tag\[Quote\].*tag\[Starred\]\]|\[tag\[Starred\].*tag\[Quote\]\]"; then
            HAS_COMBINED_TAG_FILTER="true"
        fi
    fi
fi

# Count how many tiddlers actually have the 'Starred' tag
# This proves the agent clicked the checkbox to test the UI
STARRED_COUNT=$(find_tiddlers_with_tag "Starred" | wc -l)

# Check TiddlyWiki server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*quote.*explorer" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$TIDDLER_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")

JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "tiddler_mtime": $TIDDLER_MTIME,
    "created_during_task": $CREATED_DURING_TASK,
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_text": "$ESCAPED_TEXT",
    "has_count_widget": $HAS_COUNT_WIDGET,
    "has_list_widget": $HAS_LIST_WIDGET,
    "has_checkbox_widget": $HAS_CHECKBOX_WIDGET,
    "has_total_quotes_filter": $HAS_TOTAL_QUOTES_FILTER,
    "has_starred_quotes_filter": $HAS_STARRED_QUOTES_FILTER,
    "has_unique_author_filter": $HAS_UNIQUE_AUTHOR_FILTER,
    "has_combined_tag_filter": $HAS_COMBINED_TAG_FILTER,
    "starred_count": $STARRED_COUNT,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/quote_explorer_result.json"

echo "Result saved to /tmp/quote_explorer_result.json"
cat /tmp/quote_explorer_result.json
echo "=== Export complete ==="