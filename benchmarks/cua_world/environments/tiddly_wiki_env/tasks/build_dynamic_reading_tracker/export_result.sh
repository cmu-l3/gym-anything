#!/bin/bash
echo "=== Exporting build_dynamic_reading_tracker result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve Macro tiddler info
MACRO_TITLE="ProgressMacro"
MACRO_EXISTS=$(tiddler_exists "$MACRO_TITLE")
MACRO_TAGS=""
MACRO_TEXT=""
if [ "$MACRO_EXISTS" = "true" ]; then
    MACRO_TAGS=$(get_tiddler_field "$MACRO_TITLE" "tags")
    MACRO_TEXT=$(get_tiddler_text "$MACRO_TITLE")
fi

# Retrieve Dashboard tiddler info
DASHBOARD_TITLE="Reading Dashboard"
DASHBOARD_EXISTS=$(tiddler_exists "$DASHBOARD_TITLE")
DASHBOARD_TEXT=""
if [ "$DASHBOARD_EXISTS" = "true" ]; then
    DASHBOARD_TEXT=$(get_tiddler_text "$DASHBOARD_TITLE")
fi

# Use TiddlyWiki's Node.js renderer to render the dashboard to static HTML
# This proves the macros actually expand properly with the field data
echo "Rendering dashboard to HTML..."
RENDER_OUTPUT_DIR="/home/ga/mywiki/output"
mkdir -p "$RENDER_OUTPUT_DIR"
chown ga:ga "$RENDER_OUTPUT_DIR"

RENDERED_HTML=""
if [ "$DASHBOARD_EXISTS" = "true" ]; then
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render 'Reading Dashboard' 'dashboard-output.html' 'text/html' > /tmp/tw_render.log 2>&1 || true"
    
    if [ -f "$RENDER_OUTPUT_DIR/dashboard-output.html" ]; then
        RENDERED_HTML=$(cat "$RENDER_OUTPUT_DIR/dashboard-output.html")
        echo "Successfully rendered dashboard HTML."
    else
        echo "Failed to render dashboard HTML."
    fi
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*progressmacro\|Dispatching 'save' task:.*reading.*dashboard" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Prepare strings for JSON
ESCAPED_MACRO_TAGS=$(json_escape "$MACRO_TAGS")
ESCAPED_MACRO_TEXT=$(json_escape "$MACRO_TEXT")
ESCAPED_DASHBOARD_TEXT=$(json_escape "$DASHBOARD_TEXT")
ESCAPED_RENDERED_HTML=$(json_escape "$RENDERED_HTML")

# Write to JSON
JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "macro_exists": $MACRO_EXISTS,
    "macro_tags": "$ESCAPED_MACRO_TAGS",
    "macro_text": "$ESCAPED_MACRO_TEXT",
    "dashboard_exists": $DASHBOARD_EXISTS,
    "dashboard_text": "$ESCAPED_DASHBOARD_TEXT",
    "rendered_html": "$ESCAPED_RENDERED_HTML",
    "gui_save_detected": $GUI_SAVE_DETECTED
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="