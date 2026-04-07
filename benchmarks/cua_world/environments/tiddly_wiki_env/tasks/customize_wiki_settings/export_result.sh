#!/bin/bash
echo "=== Exporting customize_wiki_settings result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/settings_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper to safely query API and get text
get_api_text() {
    local encoded_title="$1"
    curl -s "http://localhost:8080/recipes/default/tiddlers/${encoded_title}" 2>/dev/null | jq -r '.text // empty' 2>/dev/null || true
}

# Fetch Site Title
TITLE_API=$(get_api_text '%24%3A%2FSiteTitle')
# Fetch Site Subtitle
SUBTITLE_API=$(get_api_text '%24%3A%2FSiteSubtitle')
# Fetch Default Tiddlers
DEFAULT_TIDDLERS_API=$(get_api_text '%24%3A%2FDefaultTiddlers')

# Check file modifications
TITLE_MODIFIED="false"
SUBTITLE_MODIFIED="false"
DEFAULT_MODIFIED="false"

if [ -f "$TIDDLER_DIR/\$__SiteTitle.tid" ]; then
    [ $(stat -c %Y "$TIDDLER_DIR/\$__SiteTitle.tid" 2>/dev/null || echo 0) -gt $TASK_START ] && TITLE_MODIFIED="true"
fi
if [ -f "$TIDDLER_DIR/\$__SiteSubtitle.tid" ]; then
    [ $(stat -c %Y "$TIDDLER_DIR/\$__SiteSubtitle.tid" 2>/dev/null || echo 0) -gt $TASK_START ] && SUBTITLE_MODIFIED="true"
fi
if [ -f "$TIDDLER_DIR/\$__DefaultTiddlers.tid" ]; then
    [ $(stat -c %Y "$TIDDLER_DIR/\$__DefaultTiddlers.tid" 2>/dev/null || echo 0) -gt $TASK_START ] && DEFAULT_MODIFIED="true"
fi

# Detect GUI Save Events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*SiteTitle\|Dispatching 'save' task:.*SiteSubtitle\|Dispatching 'save' task:.*DefaultTiddlers" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape text for JSON export
ESCAPED_TITLE=$(json_escape "$TITLE_API")
ESCAPED_SUBTITLE=$(json_escape "$SUBTITLE_API")
ESCAPED_DEFAULT=$(json_escape "$DEFAULT_TIDDLERS_API")

# Build JSON Result
JSON_RESULT=$(cat << EOF
{
    "site_title": "$ESCAPED_TITLE",
    "site_subtitle": "$ESCAPED_SUBTITLE",
    "default_tiddlers": "$ESCAPED_DEFAULT",
    "title_modified_during_task": $TITLE_MODIFIED,
    "subtitle_modified_during_task": $SUBTITLE_MODIFIED,
    "default_tiddlers_modified_during_task": $DEFAULT_MODIFIED,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/customize_settings_result.json"

echo "Result saved to /tmp/customize_settings_result.json"
cat /tmp/customize_settings_result.json
echo "=== Export complete ==="