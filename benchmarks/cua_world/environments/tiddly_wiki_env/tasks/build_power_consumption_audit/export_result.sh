#!/bin/bash
echo "=== Exporting build_power_consumption_audit result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before altering state
take_screenshot /tmp/power_audit_final.png

EXPECTED_TITLE="Power Consumption Audit"
TIDDLER_FOUND="false"
TIDDLER_TAGS=""
TIDDLER_TEXT=""

# Extract the created tiddler's raw text and tags
if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    TIDDLER_FOUND="true"
    TIDDLER_TAGS=$(get_tiddler_field "$EXPECTED_TITLE" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
fi

# Determine if the UI was used to save the file
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*power.*consumption.*audit" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# ==============================================================================
# DYNAMIC VERIFICATION INJECTION
# We inject a new appliance to test if the grand total is dynamically calculated
# Initial sum is 3240 Wh. Microwave adds 1000 * 0.2 = 200 Wh. New total: 3440 Wh.
# ==============================================================================
echo "Injecting new appliance data for dynamic verification..."

cat > "$TIDDLER_DIR/Microwave.tid" << 'EOF'
title: Microwave
tags: Appliance
power_watts: 1000
hours_per_day: 0.2

Kitchen microwave used for reheating meals.
EOF

chown ga:ga "$TIDDLER_DIR/Microwave.tid"

# Wait for TW server to catch up
sleep 2

# Render the Power Consumption Audit tiddler to static HTML using TiddlyWiki CLI
# This forces the filter expressions to evaluate against the newly injected state
echo "Rendering the dashboard to HTML..."
su - ga -c "cd /home/ga && tiddlywiki mywiki --render 'Power Consumption Audit' 'audit.html' 'text/html'" > /dev/null 2>&1

RENDERED_HTML=""
if [ -f "/home/ga/mywiki/output/audit.html" ]; then
    RENDERED_HTML=$(cat "/home/ga/mywiki/output/audit.html")
    echo "Successfully rendered dashboard."
else
    echo "WARNING: Failed to render HTML output."
fi

# Clean up the injected data so the state is clean if inspected manually later
rm -f "$TIDDLER_DIR/Microwave.tid"

# Escape text for JSON packaging
ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")
ESCAPED_HTML=$(json_escape "$RENDERED_HTML")

# Create the final result JSON payload
JSON_RESULT=$(cat << EOF
{
    "tiddler_found": $TIDDLER_FOUND,
    "tiddler_tags": "$ESCAPED_TAGS",
    "tiddler_text": "$ESCAPED_TEXT",
    "rendered_html": "$ESCAPED_HTML",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/power_audit_result.json"

echo "Result saved to /tmp/power_audit_result.json"
echo "=== Export complete ==="