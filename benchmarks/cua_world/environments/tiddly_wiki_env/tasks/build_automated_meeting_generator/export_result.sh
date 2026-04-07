#!/bin/bash
echo "=== Exporting build_automated_meeting_generator result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract Template Information
TEMPLATE_TITLE="Retrospective Template"
TEMPLATE_EXISTS=$(tiddler_exists "$TEMPLATE_TITLE")
TEMPLATE_TEXT=""
if [ "$TEMPLATE_EXISTS" = "true" ]; then
    TEMPLATE_TEXT=$(get_tiddler_text "$TEMPLATE_TITLE")
fi

# Extract Dashboard Information
DASHBOARD_TITLE="Retrospective Dashboard"
DASHBOARD_EXISTS=$(tiddler_exists "$DASHBOARD_TITLE")
DASHBOARD_TEXT=""
HAS_BUTTON="false"
HAS_NOW_MACRO="false"

if [ "$DASHBOARD_EXISTS" = "true" ]; then
    DASHBOARD_TEXT=$(get_tiddler_text "$DASHBOARD_TITLE")
    echo "$DASHBOARD_TEXT" | grep -qi "<$button" && HAS_BUTTON="true"
    echo "$DASHBOARD_TEXT" | grep -qi "<<now" && HAS_NOW_MACRO="true"
fi

# Look for the generated Sprint Retrospective tiddler created DURING the task
# Search for files starting with "Sprint Retrospective -" that are newer than task start marker
OUTPUT_FOUND="false"
OUTPUT_TITLE=""
OUTPUT_TAGS=""
OUTPUT_TEXT=""

# Find matching file created after task start
MATCH_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -name "Sprint Retrospective - [0-9][0-9][0-9][0-9]*.tid" -newer /tmp/task_start_marker 2>/dev/null | head -1)

if [ -n "$MATCH_FILE" ]; then
    OUTPUT_FOUND="true"
    OUTPUT_TITLE=$(grep "^title:" "$MATCH_FILE" | head -1 | sed 's/^title: *//')
    OUTPUT_TAGS=$(grep "^tags:" "$MATCH_FILE" | head -1 | sed 's/^tags: *//')
    OUTPUT_TEXT=$(awk '/^$/{found=1; next} found{print}' "$MATCH_FILE")
fi

# Verify TiddlyWiki GUI saves in the log
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape text for JSON
ESCAPED_TEMPLATE_TEXT=$(json_escape "$TEMPLATE_TEXT")
ESCAPED_DASHBOARD_TEXT=$(json_escape "$DASHBOARD_TEXT")
ESCAPED_OUTPUT_TITLE=$(json_escape "$OUTPUT_TITLE")
ESCAPED_OUTPUT_TAGS=$(json_escape "$OUTPUT_TAGS")
ESCAPED_OUTPUT_TEXT=$(json_escape "$OUTPUT_TEXT")

# Compile Results into JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "template_exists": $TEMPLATE_EXISTS,
    "template_text": "$ESCAPED_TEMPLATE_TEXT",
    "dashboard_exists": $DASHBOARD_EXISTS,
    "dashboard_text": "$ESCAPED_DASHBOARD_TEXT",
    "dashboard_has_button": $HAS_BUTTON,
    "dashboard_has_now_macro": $HAS_NOW_MACRO,
    "output_found": $OUTPUT_FOUND,
    "output_title": "$ESCAPED_OUTPUT_TITLE",
    "output_tags": "$ESCAPED_OUTPUT_TAGS",
    "output_text": "$ESCAPED_OUTPUT_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/meeting_generator_result.json 2>/dev/null || sudo rm -f /tmp/meeting_generator_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/meeting_generator_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/meeting_generator_result.json
chmod 666 /tmp/meeting_generator_result.json 2>/dev/null || sudo chmod 666 /tmp/meeting_generator_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/meeting_generator_result.json"
cat /tmp/meeting_generator_result.json
echo "=== Export complete ==="