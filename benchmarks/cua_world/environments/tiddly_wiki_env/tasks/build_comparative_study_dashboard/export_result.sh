#!/bin/bash
echo "=== Exporting build_comparative_study_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

EXPECTED_TITLE="Energy Comparison Dashboard"
DASHBOARD_FOUND="false"
DASHBOARD_TAGS=""
DASHBOARD_TEXT=""
CREATED_DURING_TASK="false"

# Look for the target tiddler
TARGET_FILE="$TIDDLER_DIR/$EXPECTED_TITLE.tid"
if [ -f "$TARGET_FILE" ]; then
    DASHBOARD_FOUND="true"
    DASHBOARD_TAGS=$(get_tiddler_field "$EXPECTED_TITLE" "tags")
    DASHBOARD_TEXT=$(get_tiddler_text "$EXPECTED_TITLE")
    
    # Check creation time to prevent gaming
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
else
    # Try case-insensitive or partial match fallback
    MATCH_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -newer /tmp/initial_tiddler_count 2>/dev/null | while IFS= read -r f; do
        TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
        if echo "$TITLE" | grep -qi "energy.*comparison\|comparative.*dashboard"; then
            echo "$f"
            break
        fi
    done)
    
    if [ -n "$MATCH_FILE" ]; then
        DASHBOARD_FOUND="true"
        DASHBOARD_TAGS=$(grep "^tags:" "$MATCH_FILE" | head -1 | sed 's/^tags: *//')
        DASHBOARD_TEXT=$(awk '/^$/{found=1; next} found{print}' "$MATCH_FILE")
        CREATED_DURING_TASK="true"
    fi
fi

# Analyze dashboard content
HAS_SELECT="false"
HAS_STATE_VAR="false"
HAS_TRANSCLUDE="false"
HAS_SOURCE_FILTER="false"
SELECT_COUNT=0

if [ -n "$DASHBOARD_TEXT" ]; then
    # Count <$select widgets
    SELECT_COUNT=$(echo "$DASHBOARD_TEXT" | grep -io "<\$select" | wc -l)
    [ $SELECT_COUNT -ge 2 ] && HAS_SELECT="true"
    
    # Look for state variables (e.g. $:/state/... )
    echo "$DASHBOARD_TEXT" | grep -q "\$:/state/" && HAS_STATE_VAR="true"
    
    # Look for transclusion (either <$transclude or {{$:/state...}})
    if echo "$DASHBOARD_TEXT" | grep -q "<\$transclude" || echo "$DASHBOARD_TEXT" | grep -q "{{.*\$:/state"; then
        HAS_TRANSCLUDE="true"
    fi
    
    # Look for EnergySource filter tag
    echo "$DASHBOARD_TEXT" | grep -q "tag\[EnergySource\]" && HAS_SOURCE_FILTER="true"
fi

# Check tags
HAS_DASHBOARD_TAG="false"
if [ -n "$DASHBOARD_TAGS" ]; then
    echo "$DASHBOARD_TAGS" | grep -qi "dashboard" && HAS_DASHBOARD_TAG="true"
fi

# Check TiddlyWiki server log for GUI save events (Anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        if grep -qi "energy.*comparison" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

# Build JSON result
ESCAPED_TAGS=$(json_escape "$DASHBOARD_TAGS")
ESCAPED_TEXT=$(json_escape "$DASHBOARD_TEXT")

JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "dashboard_found": $DASHBOARD_FOUND,
    "dashboard_tags": "$ESCAPED_TAGS",
    "dashboard_text": "$ESCAPED_TEXT",
    "created_during_task": $CREATED_DURING_TASK,
    "has_select_widgets": $HAS_SELECT,
    "select_count": $SELECT_COUNT,
    "has_state_var": $HAS_STATE_VAR,
    "has_transclude": $HAS_TRANSCLUDE,
    "has_source_filter": $HAS_SOURCE_FILTER,
    "has_dashboard_tag": $HAS_DASHBOARD_TAG,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="