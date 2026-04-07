#!/bin/bash
echo "=== Exporting build_master_detail_explorer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TARGET="Medication Explorer"
TIDDLER_EXISTS=$(tiddler_exists "$TARGET")
TIDDLER_TAGS=""
TIDDLER_TEXT=""
HAS_DASHBOARD_TAG="false"

# Metrics variables
HAS_FLEX_LAYOUT="false"
HAS_LIST_WIDGET="false"
HAS_STATE_BUTTON="false"
HAS_DYNAMIC_CONTEXT="false"
HAS_CLASS_FIELD="false"
HAS_IND_FIELD="false"
HAS_SE_FIELD="false"
HAS_EMPTY_STATE="false"
GUI_SAVE_DETECTED="false"

if [ "$TIDDLER_EXISTS" = "true" ]; then
    TIDDLER_TAGS=$(get_tiddler_field "$TARGET" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$TARGET")
    
    # Check Tag
    if echo "$TIDDLER_TAGS" | grep -qi "dashboard"; then
        HAS_DASHBOARD_TAG="true"
    fi
    
    # Check Layout CSS/HTML patterns
    if echo "$TIDDLER_TEXT" | grep -qiE "flex|grid|width.*%|width.*vw|float|column"; then
        HAS_FLEX_LAYOUT="true"
    fi
    
    # Check List widget
    if echo "$TIDDLER_TEXT" | grep -qiE "<\$list.*tag\[Medication\]|\[tag\[Medication\]\]"; then
        HAS_LIST_WIDGET="true"
    fi
    
    # Check State Button mutation (button setting state OR action-setfield)
    if echo "$TIDDLER_TEXT" | grep -qiE "<\$button.*set=.*state|<\$action-setfield.*state"; then
        HAS_STATE_BUTTON="true"
    fi
    
    # Check Context Transclusion (referencing state or changing tiddler context)
    if echo "$TIDDLER_TEXT" | grep -qiE "state|currentTiddler|<\$tiddler|{{{"; then
        HAS_DYNAMIC_CONTEXT="true"
    fi
    
    # Check Field Transclusion 
    if echo "$TIDDLER_TEXT" | grep -qiE "!!drug-class|drug-class"; then
        HAS_CLASS_FIELD="true"
    fi
    if echo "$TIDDLER_TEXT" | grep -qiE "!!indications|indications"; then
        HAS_IND_FIELD="true"
    fi
    if echo "$TIDDLER_TEXT" | grep -qiE "!!common-side-effects|common-side-effects"; then
        HAS_SE_FIELD="true"
    fi
    
    # Check Empty State handling
    if echo "$TIDDLER_TEXT" | grep -qiE "Please select a medication\."; then
        HAS_EMPTY_STATE="true"
    fi
fi

# Check Server logs for anti-gaming (GUI save detection)
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*medication.*explorer" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build JSON
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")
ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")

JSON_RESULT=$(cat << EOF
{
    "tiddler_exists": $TIDDLER_EXISTS,
    "has_dashboard_tag": $HAS_DASHBOARD_TAG,
    "tiddler_tags": "$ESCAPED_TAGS",
    "has_flex_layout": $HAS_FLEX_LAYOUT,
    "has_list_widget": $HAS_LIST_WIDGET,
    "has_state_button": $HAS_STATE_BUTTON,
    "has_dynamic_context": $HAS_DYNAMIC_CONTEXT,
    "has_class_field": $HAS_CLASS_FIELD,
    "has_ind_field": $HAS_IND_FIELD,
    "has_se_field": $HAS_SE_FIELD,
    "has_empty_state": $HAS_EMPTY_STATE,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "tiddler_text": "$ESCAPED_TEXT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="