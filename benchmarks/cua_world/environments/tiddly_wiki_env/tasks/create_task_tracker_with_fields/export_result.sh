#!/bin/bash
echo "=== Exporting create_task_tracker_with_fields result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/tracker_final.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

declare -a TITLES=(
    "Migrate Database to PostgreSQL 16"
    "Update API Documentation"
    "Fix Authentication Timeout Bug"
    "Design New Dashboard Mockups"
    "Set Up CI-CD Pipeline for Staging"
)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "{\"tasks\": {}, \"sprint_board\": {}, \"gui_save\": false}" > "$TEMP_JSON"

# Check each task
for title in "${TITLES[@]}"; do
    exists=$(tiddler_exists "$title")
    created_after="false"
    has_tag="false"
    priority=""
    assignee=""
    status=""
    due_date=""

    if [ "$exists" = "true" ]; then
        sanitized=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
        file="$TIDDLER_DIR/${sanitized}.tid"
        if [ ! -f "$file" ]; then
            file=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
        fi
        
        if [ -f "$file" ]; then
            MTIME=$(stat -c %Y "$file" 2>/dev/null || echo "0")
            if [ "$MTIME" -gt "$START_TIME" ]; then
                created_after="true"
            fi
        fi
        
        tags=$(get_tiddler_field "$title" "tags")
        if echo "$tags" | grep -qi "Sprint-Tasks"; then
            has_tag="true"
        fi
        
        priority=$(get_tiddler_field "$title" "priority" | tr -d '\r')
        assignee=$(get_tiddler_field "$title" "assignee" | tr -d '\r')
        status=$(get_tiddler_field "$title" "status" | tr -d '\r')
        due_date=$(get_tiddler_field "$title" "due-date" | tr -d '\r')
    fi
    
    jq --arg t "$title" \
       --arg e "$exists" \
       --arg c "$created_after" \
       --arg tag "$has_tag" \
       --arg p "$priority" \
       --arg a "$assignee" \
       --arg s "$status" \
       --arg d "$due_date" \
       '.tasks[$t] = {exists: ($e=="true"), created_after: ($c=="true"), has_tag: ($tag=="true"), priority: $p, assignee: $a, status: $s, due_date: $d}' "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"
done

# Check Sprint Board
SB_TITLE="Sprint Board"
SB_EXISTS=$(tiddler_exists "$SB_TITLE")
SB_CREATED_AFTER="false"
HAS_OPEN_FILTER="false"
HAS_HIGH_FILTER="false"
HAS_OPEN_HEADING="false"
HAS_HIGH_HEADING="false"
HAS_LIST_WIDGET="false"

if [ "$SB_EXISTS" = "true" ]; then
    sb_sanitized=$(echo "$SB_TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
    file="$TIDDLER_DIR/${sb_sanitized}.tid"
    if [ ! -f "$file" ]; then
        file=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sb_sanitized}.tid" 2>/dev/null | head -1)
    fi
    
    if [ -f "$file" ]; then
        MTIME=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$START_TIME" ]; then
            SB_CREATED_AFTER="true"
        fi
    fi
    
    SB_TEXT=$(get_tiddler_text "$SB_TITLE")
    
    # Check filters with various valid syntaxes
    if echo "$SB_TEXT" | grep -qE "status\[open\]|status\[\[open\]\]|field:status\[open\]|field:status\[\[open\]\]|status=open"; then
        HAS_OPEN_FILTER="true"
    fi
    
    if echo "$SB_TEXT" | grep -qE "priority\[high\]|priority\[\[high\]\]|field:priority\[high\]|field:priority\[\[high\]\]|priority=high"; then
        HAS_HIGH_FILTER="true"
    fi
    
    # Check headings
    if echo "$SB_TEXT" | grep -qi "Open Tasks"; then
        HAS_OPEN_HEADING="true"
    fi
    
    if echo "$SB_TEXT" | grep -qi "High Priority"; then
        HAS_HIGH_HEADING="true"
    fi
    
    # Check for $list widget
    if echo "$SB_TEXT" | grep -qE "<\$list|<list"; then
        HAS_LIST_WIDGET="true"
    fi
fi

jq --arg e "$SB_EXISTS" \
   --arg c "$SB_CREATED_AFTER" \
   --arg of "$HAS_OPEN_FILTER" \
   --arg hf "$HAS_HIGH_FILTER" \
   --arg oh "$HAS_OPEN_HEADING" \
   --arg hh "$HAS_HIGH_HEADING" \
   --arg lw "$HAS_LIST_WIDGET" \
   '.sprint_board = {exists: ($e=="true"), created_after: ($c=="true"), has_open_filter: ($of=="true"), has_high_filter: ($hf=="true"), has_open_heading: ($oh=="true"), has_high_heading: ($hh=="true"), has_list_widget: ($lw=="true")}' "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"

# Check GUI saves via server log
GUI_SAVE="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE="true"
    fi
fi

jq --arg gs "$GUI_SAVE" '.gui_save = ($gs=="true")' "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"

# Safely copy to /tmp for verification hook
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="