#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for trajectory history
take_screenshot /tmp/task_final.png

# Find the target tiddler created by the agent
TARGET_TITLE="Interactive Deployment Generator"
TIDDLER_FOUND="false"
RAW_TEXT=""
TAGS=""

# Look for exact match first
if [ "$(tiddler_exists "$TARGET_TITLE")" = "true" ]; then
    TIDDLER_FOUND="true"
    RAW_TEXT=$(get_tiddler_text "$TARGET_TITLE")
    TAGS=$(get_tiddler_field "$TARGET_TITLE" "tags")
else
    # Fallback to loose title matching in case of minor typos
    MATCH=$(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' | while read f; do
        if grep -qi "^title:.*Interactive.*Deployment" "$f"; then
            echo "$f"
            break
        fi
    done)
    if [ -n "$MATCH" ]; then
        TIDDLER_FOUND="true"
        TARGET_TITLE=$(grep "^title:" "$MATCH" | head -1 | sed 's/^title: *//')
        RAW_TEXT=$(awk '/^$/{found=1; next} found{print}' "$MATCH")
        TAGS=$(grep "^tags:" "$MATCH" | head -1 | sed 's/^tags: *//')
    fi
fi

RENDER1_HTML=""
RENDER2_HTML=""

if [ "$TIDDLER_FOUND" = "true" ]; then
    echo "Tiddler found! Performing dynamic render anti-gaming tests..."

    # =====================================================================
    # TEST 1: Inject State Set 1 and Render
    # =====================================================================
    echo "title: \$:/state/deploy/app" > "$TIDDLER_DIR/test_state_app.tid"
    echo "" >> "$TIDDLER_DIR/test_state_app.tid"
    echo "auth-service" >> "$TIDDLER_DIR/test_state_app.tid"

    echo "title: \$:/state/deploy/tag" > "$TIDDLER_DIR/test_state_tag.tid"
    echo "" >> "$TIDDLER_DIR/test_state_tag.tid"
    echo "v2.0" >> "$TIDDLER_DIR/test_state_tag.tid"

    echo "title: \$:/state/deploy/port" > "$TIDDLER_DIR/test_state_port.tid"
    echo "" >> "$TIDDLER_DIR/test_state_port.tid"
    echo "8080" >> "$TIDDLER_DIR/test_state_port.tid"

    chown ga:ga "$TIDDLER_DIR/test_state_"*.tid

    # Render offline via Node.js CLI to safely capture the interpolated output
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render \"$TARGET_TITLE\" \"render1.html\" \"text/html\" \"\$:/core/templates/tiddler\""
    
    if [ -f "/home/ga/mywiki/output/render1.html" ]; then
        RENDER1_HTML=$(cat "/home/ga/mywiki/output/render1.html")
    fi

    # =====================================================================
    # TEST 2: Inject State Set 2 and Render (Ensures reactivity)
    # =====================================================================
    echo "title: \$:/state/deploy/app" > "$TIDDLER_DIR/test_state_app.tid"
    echo "" >> "$TIDDLER_DIR/test_state_app.tid"
    echo "payment-api" >> "$TIDDLER_DIR/test_state_app.tid"

    echo "title: \$:/state/deploy/tag" > "$TIDDLER_DIR/test_state_tag.tid"
    echo "" >> "$TIDDLER_DIR/test_state_tag.tid"
    echo "latest" >> "$TIDDLER_DIR/test_state_tag.tid"

    echo "title: \$:/state/deploy/port" > "$TIDDLER_DIR/test_state_port.tid"
    echo "" >> "$TIDDLER_DIR/test_state_port.tid"
    echo "9000" >> "$TIDDLER_DIR/test_state_port.tid"

    # Render again
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render \"$TARGET_TITLE\" \"render2.html\" \"text/html\" \"\$:/core/templates/tiddler\""
    
    if [ -f "/home/ga/mywiki/output/render2.html" ]; then
        RENDER2_HTML=$(cat "/home/ga/mywiki/output/render2.html")
    fi

    # Cleanup test states
    rm -f "$TIDDLER_DIR/test_state_"*.tid
fi

# Package JSON safely handling all newlines and quotes
ESCAPED_TITLE=$(json_escape "$TARGET_TITLE")
ESCAPED_TAGS=$(json_escape "$TAGS")
ESCAPED_TEXT=$(json_escape "$RAW_TEXT")
ESCAPED_R1=$(json_escape "$RENDER1_HTML")
ESCAPED_R2=$(json_escape "$RENDER2_HTML")

JSON_RESULT=$(cat << EOF
{
    "tiddler_found": $TIDDLER_FOUND,
    "tiddler_title": "$ESCAPED_TITLE",
    "tags": "$ESCAPED_TAGS",
    "raw_text": "$ESCAPED_TEXT",
    "render1_html": "$ESCAPED_R1",
    "render2_html": "$ESCAPED_R2",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="