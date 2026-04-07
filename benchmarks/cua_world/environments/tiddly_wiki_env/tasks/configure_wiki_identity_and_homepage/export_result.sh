#!/bin/bash
echo "=== Exporting configure_wiki_identity_and_homepage result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve system tiddlers
SITE_TITLE=$(get_tiddler_text "\$:/SiteTitle" | tr -d '\n' | tr -d '\r')
SITE_SUBTITLE=$(get_tiddler_text "\$:/SiteSubtitle" | tr -d '\n' | tr -d '\r')
DEFAULT_TIDDLERS=$(get_tiddler_text "\$:/DefaultTiddlers" | tr -d '\n' | tr -d '\r')

# Retrieve custom homepage
HOMEPAGE_TITLE="Kafka Knowledge Base"
HOMEPAGE_EXISTS=$(tiddler_exists "$HOMEPAGE_TITLE")
HOMEPAGE_TEXT=""

if [ "$HOMEPAGE_EXISTS" = "true" ]; then
    HOMEPAGE_TEXT=$(get_tiddler_text "$HOMEPAGE_TITLE")
fi

# Check timestamps of modified files
TITLE_MTIME=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "\$__SiteTitle.tid" -exec stat -c %Y {} + 2>/dev/null | head -1 || echo "0")
if [ -z "$TITLE_MTIME" ]; then TITLE_MTIME="0"; fi

SUBTITLE_MTIME=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "\$__SiteSubtitle.tid" -exec stat -c %Y {} + 2>/dev/null | head -1 || echo "0")
if [ -z "$SUBTITLE_MTIME" ]; then SUBTITLE_MTIME="0"; fi

DEFAULT_MTIME=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "\$__DefaultTiddlers.tid" -exec stat -c %Y {} + 2>/dev/null | head -1 || echo "0")
if [ -z "$DEFAULT_MTIME" ]; then DEFAULT_MTIME="0"; fi

HOMEPAGE_MTIME=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "Kafka*Knowledge*Base.tid" -exec stat -c %Y {} + 2>/dev/null | head -1 || echo "0")
if [ -z "$HOMEPAGE_MTIME" ]; then HOMEPAGE_MTIME="0"; fi

# Check TiddlyWiki server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*SiteTitle|Dispatching 'save' task:.*SiteSubtitle|Dispatching 'save' task:.*DefaultTiddlers|Dispatching 'save' task:.*Kafka" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

ESCAPED_SITE_TITLE=$(json_escape "$SITE_TITLE")
ESCAPED_SITE_SUBTITLE=$(json_escape "$SITE_SUBTITLE")
ESCAPED_DEFAULT_TIDDLERS=$(json_escape "$DEFAULT_TIDDLERS")
ESCAPED_HOMEPAGE_TEXT=$(json_escape "$HOMEPAGE_TEXT")

JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "site_title": "$ESCAPED_SITE_TITLE",
    "site_subtitle": "$ESCAPED_SITE_SUBTITLE",
    "default_tiddlers": "$ESCAPED_DEFAULT_TIDDLERS",
    "homepage_exists": $HOMEPAGE_EXISTS,
    "homepage_text": "$ESCAPED_HOMEPAGE_TEXT",
    "title_mtime": $TITLE_MTIME,
    "subtitle_mtime": $SUBTITLE_MTIME,
    "default_mtime": $DEFAULT_MTIME,
    "homepage_mtime": $HOMEPAGE_MTIME,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="