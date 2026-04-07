#!/bin/bash
echo "=== Exporting build_dynamic_recipe_scaler result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/scaler_final.png

TARGET="Baguette Calculator"
TIDDLER_EXISTS=$(tiddler_exists "$TARGET")
TIDDLER_TEXT=$(get_tiddler_text "$TARGET")
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")

STATE_TARGET='$:/state/baguette-yield'
STATE_EXISTS=$(tiddler_exists "$STATE_TARGET")
STATE_TEXT=$(get_tiddler_text "$STATE_TARGET")

# Test rendering output
TEST1_HTML=""
TEST3_HTML=""
TEST10_HTML=""

if [ "$TIDDLER_EXISTS" = "true" ]; then
    STATE_FILE="$TIDDLER_DIR/\$__state_baguette-yield.tid"
    
    # Save original state if it exists
    if [ -f "$STATE_FILE" ]; then
        cp "$STATE_FILE" /tmp/orig_state.tid
    else
        cat > /tmp/orig_state.tid << EOF
title: $STATE_TARGET

1
EOF
    fi
    
    mkdir -p /home/ga/mywiki/output
    chown ga:ga /home/ga/mywiki/output
    
    # Test 1x Scaling
    cat > "$STATE_FILE" << EOF
title: $STATE_TARGET

1
EOF
    chown ga:ga "$STATE_FILE"
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render '$TARGET' 'test1.html'"
    TEST1_HTML=$(cat /home/ga/mywiki/output/test1.html 2>/dev/null || echo "")
    
    # Test 3x Scaling
    cat > "$STATE_FILE" << EOF
title: $STATE_TARGET

3
EOF
    chown ga:ga "$STATE_FILE"
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render '$TARGET' 'test3.html'"
    TEST3_HTML=$(cat /home/ga/mywiki/output/test3.html 2>/dev/null || echo "")
    
    # Test 10x Scaling
    cat > "$STATE_FILE" << EOF
title: $STATE_TARGET

10
EOF
    chown ga:ga "$STATE_FILE"
    su - ga -c "cd /home/ga/mywiki && tiddlywiki --render '$TARGET' 'test10.html'"
    TEST10_HTML=$(cat /home/ga/mywiki/output/test10.html 2>/dev/null || echo "")
    
    # Restore original state
    cp /tmp/orig_state.tid "$STATE_FILE"
    chown ga:ga "$STATE_FILE"
fi

ESCAPED_TEST1=$(json_escape "$TEST1_HTML")
ESCAPED_TEST3=$(json_escape "$TEST3_HTML")
ESCAPED_TEST10=$(json_escape "$TEST10_HTML")

# Check TiddlyWiki server log for GUI save events (anti-gaming verification)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -iE "Dispatching 'save' task:.*baguette.*calculator" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

JSON_RESULT=$(cat << EOF
{
    "calculator_exists": $TIDDLER_EXISTS,
    "calculator_text": "$ESCAPED_TEXT",
    "state_exists": $STATE_EXISTS,
    "state_text": "$(json_escape "$STATE_TEXT")",
    "test1_html": "$ESCAPED_TEST1",
    "test3_html": "$ESCAPED_TEST3",
    "test10_html": "$ESCAPED_TEST10",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/recipe_scaler_result.json"
echo "Result saved to /tmp/recipe_scaler_result.json"
echo "=== Export complete ==="