#!/bin/bash
echo "=== Exporting build_tiddler_generator_form result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

FORM_TITLE="New Patient Registration Form"
FORM_EXISTS=$(tiddler_exists "$FORM_TITLE")
FORM_TEXT=""

# Extract the entire content of the form tiddler
if [ "$FORM_EXISTS" = "true" ]; then
    FORM_TEXT=$(get_tiddler_content "$FORM_TITLE")
fi

# Detect if the tiddler was saved legitimately through the GUI 
# (anti-gaming to prevent pure bash string echoing)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*new.*patient.*registration.*form" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Escape the raw tiddler code safely for JSON transport
ESCAPED_TEXT=$(json_escape "$FORM_TEXT")

# Build the JSON payload to send back to the Python verifier
JSON_RESULT=$(cat << EOF
{
    "form_exists": $FORM_EXISTS,
    "form_text": "$ESCAPED_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Use utility to safely write JSON cross-permissions
write_result_json "$JSON_RESULT" "/tmp/form_task_result.json"

echo "Result saved to /tmp/form_task_result.json"
echo "=== Export complete ==="