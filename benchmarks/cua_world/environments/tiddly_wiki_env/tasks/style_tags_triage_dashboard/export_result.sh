#!/bin/bash
echo "=== Exporting style_tags_triage_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Check tags for bug
BUG_EXISTS=$(tiddler_exists "bug")
BUG_COLOR=$(get_tiddler_field "bug" "color")
BUG_ICON=$(get_tiddler_field "bug" "icon")

# Check tags for enhancement
ENH_EXISTS=$(tiddler_exists "enhancement")
ENH_COLOR=$(get_tiddler_field "enhancement" "color")
ENH_ICON=$(get_tiddler_field "enhancement" "icon")

# Check tags for documentation
DOC_EXISTS=$(tiddler_exists "documentation")
DOC_COLOR=$(get_tiddler_field "documentation" "color")
DOC_ICON=$(get_tiddler_field "documentation" "icon")

# Check Dashboard
DASH_TITLE="Triage Dashboard"
DASH_EXISTS=$(tiddler_exists "$DASH_TITLE")
DASH_TAGS=$(get_tiddler_field "$DASH_TITLE" "tags")
DASH_CAPTION=$(get_tiddler_field "$DASH_TITLE" "caption")
DASH_TEXT=$(get_tiddler_text "$DASH_TITLE")

# Extract Headers Presence
HAS_H_CRITICAL="false"
HAS_H_ENHANCEMENT="false"
HAS_H_DOCUMENTATION="false"

if [ -n "$DASH_TEXT" ]; then
    echo "$DASH_TEXT" | grep -qi "^!! *Critical Bugs" && HAS_H_CRITICAL="true"
    echo "$DASH_TEXT" | grep -qi "^!! *Enhancements" && HAS_H_ENHANCEMENT="true"
    echo "$DASH_TEXT" | grep -qi "^!! *Documentation" && HAS_H_DOCUMENTATION="true"
fi

# Detect GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qiE "Dispatching 'save' task:.*(bug|enhancement|documentation|triage.*dashboard)" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build JSON Result safely
ESCAPED_DASH_TAGS=$(json_escape "$DASH_TAGS")
ESCAPED_DASH_CAPTION=$(json_escape "$DASH_CAPTION")
ESCAPED_DASH_TEXT=$(json_escape "$DASH_TEXT")
ESCAPED_BUG_COLOR=$(json_escape "$BUG_COLOR")
ESCAPED_BUG_ICON=$(json_escape "$BUG_ICON")
ESCAPED_ENH_COLOR=$(json_escape "$ENH_COLOR")
ESCAPED_ENH_ICON=$(json_escape "$ENH_ICON")
ESCAPED_DOC_COLOR=$(json_escape "$DOC_COLOR")
ESCAPED_DOC_ICON=$(json_escape "$DOC_ICON")

JSON_RESULT=$(cat << EOF
{
    "bug": {
        "exists": $BUG_EXISTS,
        "color": "$ESCAPED_BUG_COLOR",
        "icon": "$ESCAPED_BUG_ICON"
    },
    "enhancement": {
        "exists": $ENH_EXISTS,
        "color": "$ESCAPED_ENH_COLOR",
        "icon": "$ESCAPED_ENH_ICON"
    },
    "documentation": {
        "exists": $DOC_EXISTS,
        "color": "$ESCAPED_DOC_COLOR",
        "icon": "$ESCAPED_DOC_ICON"
    },
    "dashboard": {
        "exists": $DASH_EXISTS,
        "tags": "$ESCAPED_DASH_TAGS",
        "caption": "$ESCAPED_DASH_CAPTION",
        "text": "$ESCAPED_DASH_TEXT",
        "has_h_critical": $HAS_H_CRITICAL,
        "has_h_enhancement": $HAS_H_ENHANCEMENT,
        "has_h_documentation": $HAS_H_DOCUMENTATION
    },
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="