#!/bin/bash
echo "=== Exporting build_interactive_runbook_wizard result ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/wizard_final.png

TARGET="Production Database Upgrade Wizard"
TIDDLER_EXISTS=$(tiddler_exists "$TARGET")
TEXT=$(get_tiddler_text "$TARGET")

# Verify transclusions (Looking for either {{Runbook...}} or <$transclude tiddler="Runbook... )
HAS_T1="false"
HAS_T2="false"
HAS_T3="false"
HAS_T4="false"
HAS_HARDCODED_CONTENT="false"

if [ -n "$TEXT" ]; then
    echo "$TEXT" | grep -qi "Runbook: 1" && HAS_T1="true"
    echo "$TEXT" | grep -qi "Runbook: 2" && HAS_T2="true"
    echo "$TEXT" | grep -qi "Runbook: 3" && HAS_T3="true"
    echo "$TEXT" | grep -qi "Runbook: 4" && HAS_T4="true"
    
    # Check if they copy-pasted instead of transcluding (looking for actual runbook commands)
    if echo "$TEXT" | grep -qi "df -h" || echo "$TEXT" | grep -qi "pg_lsclusters" || echo "$TEXT" | grep -qi "pg_upgrade -b"; then
        HAS_HARDCODED_CONTENT="true"
    fi
fi

# Check for required widgets
HAS_REVEAL="false"
HAS_MATCH="false"
HAS_BUTTON="false"
HAS_MUTATION="false"

if [ -n "$TEXT" ]; then
    echo "$TEXT" | grep -qi "<\$reveal" && HAS_REVEAL="true"
    echo "$TEXT" | grep -qi "type=[\"']match\|type=[\"']nomatch" && HAS_MATCH="true"
    echo "$TEXT" | grep -qi "<\$button" && HAS_BUTTON="true"
    echo "$TEXT" | grep -qi "set=\|setTo=\|<\$action-setfield" && HAS_MUTATION="true"
fi

# Check TiddlyWiki server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*production.*database\|Dispatching 'save' task:.*upgrade.*wizard" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

ESCAPED_TEXT=$(json_escape "$TEXT")

JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "has_t1_reference": $HAS_T1,
    "has_t2_reference": $HAS_T2,
    "has_t3_reference": $HAS_T3,
    "has_t4_reference": $HAS_T4,
    "has_hardcoded_content": $HAS_HARDCODED_CONTENT,
    "has_reveal_widget": $HAS_REVEAL,
    "has_match_type": $HAS_MATCH,
    "has_button_widget": $HAS_BUTTON,
    "has_state_mutation": $HAS_MUTATION,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "tiddler_text": "$ESCAPED_TEXT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/wizard_result.json"

echo "Result saved to /tmp/wizard_result.json"
cat /tmp/wizard_result.json
echo "=== Export complete ==="