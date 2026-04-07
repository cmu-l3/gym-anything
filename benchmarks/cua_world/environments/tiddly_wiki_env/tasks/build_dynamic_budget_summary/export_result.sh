#!/bin/bash
echo "=== Exporting build_dynamic_budget_summary result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/budget_final.png

TIDDLER_TITLE="Japan Trip Budget Summary"
TIDDLER_FOUND="false"
TIDDLER_TAGS=""
TIDDLER_TEXT=""
USES_SUM_FILTER="false"

# Check if tiddler exists
if [ "$(tiddler_exists "$TIDDLER_TITLE")" = "true" ]; then
    TIDDLER_FOUND="true"
    TIDDLER_TAGS=$(get_tiddler_field "$TIDDLER_TITLE" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$TIDDLER_TITLE")
    
    # Check raw text for sum operators (anti-gaming text check)
    if echo "$TIDDLER_TEXT" | grep -qi "sum\[\]"; then
        USES_SUM_FILTER="true"
    fi
fi

# =====================================================================
# ANTI-GAMING: DYNAMIC RENDER TEST
# We render the tiddler to plain text, inject a new expense, and render again
# to verify that the filters actually calculate dynamically.
# =====================================================================

INITIAL_RENDER_TEXT=""
FINAL_RENDER_TEXT=""

if [ "$TIDDLER_FOUND" = "true" ]; then
    echo "Rendering initial state..."
    # Render tiddler as plain text to evaluate macros/filters
    su - ga -c "cd /home/ga/mywiki && tiddlywiki . --render '$TIDDLER_TITLE' 'budget_initial.txt' 'text/plain' '\$:/core/templates/tiddler-body-text'" > /dev/null 2>&1
    
    if [ -f "/home/ga/mywiki/output/budget_initial.txt" ]; then
        INITIAL_RENDER_TEXT=$(cat "/home/ga/mywiki/output/budget_initial.txt")
    fi
    
    echo "Injecting hidden surprise expense to test dynamicity..."
    cat > "/home/ga/mywiki/tiddlers/Surprise Expense.tid" << 'EOF'
title: Surprise Expense
tags: Japan2026
category: Activity
cost: 5000

Hidden verification expense!
EOF
    chown ga:ga "/home/ga/mywiki/tiddlers/Surprise Expense.tid"
    
    echo "Rendering final dynamic state..."
    su - ga -c "cd /home/ga/mywiki && tiddlywiki . --render '$TIDDLER_TITLE' 'budget_final.txt' 'text/plain' '\$:/core/templates/tiddler-body-text'" > /dev/null 2>&1
    
    if [ -f "/home/ga/mywiki/output/budget_final.txt" ]; then
        FINAL_RENDER_TEXT=$(cat "/home/ga/mywiki/output/budget_final.txt")
    fi
fi

# Check for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*japan.*budget" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")
ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")
ESCAPED_INITIAL_RENDER=$(json_escape "$INITIAL_RENDER_TEXT")
ESCAPED_FINAL_RENDER=$(json_escape "$FINAL_RENDER_TEXT")

JSON_RESULT=$(cat << EOF
{
    "tiddler_found": $TIDDLER_FOUND,
    "tiddler_tags": "$ESCAPED_TAGS",
    "raw_text": "$ESCAPED_TEXT",
    "uses_sum_filter": $USES_SUM_FILTER,
    "initial_render_text": "$ESCAPED_INITIAL_RENDER",
    "final_render_text": "$ESCAPED_FINAL_RENDER",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/budget_summary_result.json"

echo "Result saved to /tmp/budget_summary_result.json"
echo "=== Export complete ==="