#!/bin/bash
echo "=== Exporting create_interactive_troubleshoot_guide result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/troubleshoot_guide_final.png

# Get initial state references
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

EXPECTED_TITLE="Troubleshooting: Internet Connectivity"

# Initialize verification variables
TIDDLER_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
REVEAL_COUNT=0
BUTTON_COUNT=0
HAS_STATE_REF="false"
HAS_ACTION_MECH="false"
HAS_CORRECT_TAGS="false"

# Content checks
HAS_GATEWAY_PHYSICAL="false"
HAS_DNS_PATH="false"
HAS_PARTIAL_ACCESS="false"
HAS_RESET_TEXT="false"

# Locate the tiddler
TIDDLER_FILE=""
if [ "$(tiddler_exists "$EXPECTED_TITLE")" = "true" ]; then
    TIDDLER_EXISTS="true"
    
    # Get the actual file path (handling TiddlyWiki's sanitization)
    SANITIZED=$(echo "$EXPECTED_TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
    TIDDLER_FILE="$TIDDLER_DIR/${SANITIZED}.tid"
    if [ ! -f "$TIDDLER_FILE" ]; then
        TIDDLER_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${SANITIZED}.tid" 2>/dev/null | head -1)
    fi
fi

if [ "$TIDDLER_EXISTS" = "true" ] && [ -f "$TIDDLER_FILE" ]; then
    # Check if created/modified during task
    FILE_MTIME=$(stat -c %Y "$TIDDLER_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi

    # Extract tags and text
    TIDDLER_TAGS=$(get_tiddler_field "$EXPECTED_TITLE" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")

    # Tag Verification
    if echo "$TIDDLER_TAGS" | grep -qi "Troubleshooting" && echo "$TIDDLER_TAGS" | grep -qi "NetworkSupport"; then
        HAS_CORRECT_TAGS="true"
    fi

    # Widget Counts
    REVEAL_COUNT=$(echo "$TIDDLER_TEXT" | grep -o -i "<$reveal" | wc -l)
    BUTTON_COUNT=$(echo "$TIDDLER_TEXT" | grep -o -i "<$button" | wc -l)

    # State mechanism verification
    if echo "$TIDDLER_TEXT" | grep -qi "\$:/state/troubleshoot-internet"; then
        HAS_STATE_REF="true"
    fi
    
    if echo "$TIDDLER_TEXT" | grep -qiE "<\\\$action-setfield|set=|setTo="; then
        HAS_ACTION_MECH="true"
    fi

    # Content Branches Verification
    if echo "$TIDDLER_TEXT" | grep -qi "default gateway" && echo "$TIDDLER_TEXT" | grep -qiE "physical layer|cable"; then
        HAS_GATEWAY_PHYSICAL="true"
    fi
    
    if echo "$TIDDLER_TEXT" | grep -qi "8.8.8.8" && echo "$TIDDLER_TEXT" | grep -qi "DNS resolution"; then
        HAS_DNS_PATH="true"
    fi
    
    if echo "$TIDDLER_TEXT" | grep -qi "speed test" && echo "$TIDDLER_TEXT" | grep -qiE "proxy|firewall"; then
        HAS_PARTIAL_ACCESS="true"
    fi
    
    if echo "$TIDDLER_TEXT" | grep -qiE "start over|reset"; then
        HAS_RESET_TEXT="true"
    fi
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*troubleshoot.*internet" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# JSON export
JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "has_correct_tags": $HAS_CORRECT_TAGS,
    "reveal_count": $REVEAL_COUNT,
    "button_count": $BUTTON_COUNT,
    "has_state_ref": $HAS_STATE_REF,
    "has_action_mech": $HAS_ACTION_MECH,
    "has_gateway_physical": $HAS_GATEWAY_PHYSICAL,
    "has_dns_path": $HAS_DNS_PATH,
    "has_partial_access": $HAS_PARTIAL_ACCESS,
    "has_reset_text": $HAS_RESET_TEXT,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/troubleshoot_guide_result.json"

echo "Result saved to /tmp/troubleshoot_guide_result.json"
cat /tmp/troubleshoot_guide_result.json
echo "=== Export complete ==="