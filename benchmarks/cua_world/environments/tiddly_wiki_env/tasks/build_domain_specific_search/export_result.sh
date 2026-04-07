#!/bin/bash
echo "=== Exporting build_domain_specific_search result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TARGET="Active Guidelines Search"
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

TIDDLER_EXISTS="false"
TIDDLER_TAGS=""
TIDDLER_TEXT=""

if [ "$(tiddler_exists "$TARGET")" = "true" ]; then
    TIDDLER_EXISTS="true"
    TIDDLER_TAGS=$(get_tiddler_field "$TARGET" "tags")
    TIDDLER_TEXT=$(get_tiddler_text "$TARGET")
fi

# ================================================================
# BEHAVIORAL RENDERING TESTS via TiddlyWiki CLI
# This forces TiddlyWiki to compile the agent's wikitext against
# different state configurations to see if the logic works.
# ================================================================

# Clean up any existing state
rm -f "$TIDDLER_DIR/\$__state_guideline-search.tid" 2>/dev/null || true

if [ "$TIDDLER_EXISTS" = "true" ]; then
    echo "Running Behavioral Test 1: Empty State"
    # Create empty state (should show all active guidelines)
    cat > "$TIDDLER_DIR/\$__state_guideline-search.tid" << 'EOF'
title: $:/state/guideline-search

EOF
    chown ga:ga "$TIDDLER_DIR/\$__state_guideline-search.tid"
    su - ga -c "tiddlywiki /home/ga/mywiki --rendertiddler 'Active Guidelines Search' /tmp/render_empty.html" 2>/dev/null || true

    echo "Running Behavioral Test 2: Targeted State ('sepsis')"
    # Create targeted state (should isolate only the Sepsis guideline)
    cat > "$TIDDLER_DIR/\$__state_guideline-search.tid" << 'EOF'
title: $:/state/guideline-search

sepsis
EOF
    chown ga:ga "$TIDDLER_DIR/\$__state_guideline-search.tid"
    su - ga -c "tiddlywiki /home/ga/mywiki --rendertiddler 'Active Guidelines Search' /tmp/render_sepsis.html" 2>/dev/null || true
fi

# Parse Test 1 Results (Empty State)
EMPTY_HAS_SEPSIS=$(grep -qi "Guideline: Sepsis Protocol" /tmp/render_empty.html 2>/dev/null && echo "true" || echo "false")
EMPTY_HAS_DKA=$(grep -qi "Diabetic Ketoacidosis" /tmp/render_empty.html 2>/dev/null && echo "true" || echo "false")
EMPTY_HAS_AMI=$(grep -qi "Acute Myocardial Infarction" /tmp/render_empty.html 2>/dev/null && echo "true" || echo "false")
EMPTY_HAS_ARCHIVED=$(grep -qi "Old COVID-19 Pathway" /tmp/render_empty.html 2>/dev/null && echo "true" || echo "false")

# Parse Test 2 Results (Targeted State)
SEPSIS_HAS_SEPSIS=$(grep -qi "Guideline: Sepsis Protocol" /tmp/render_sepsis.html 2>/dev/null && echo "true" || echo "false")
SEPSIS_HAS_DKA=$(grep -qi "Diabetic Ketoacidosis" /tmp/render_sepsis.html 2>/dev/null && echo "true" || echo "false")
SEPSIS_HAS_ARCHIVED=$(grep -qi "Old COVID-19 Pathway" /tmp/render_sepsis.html 2>/dev/null && echo "true" || echo "false")
SEPSIS_HAS_MEETING=$(grep -qi "Meeting Minutes: Q3 Nursing Staff" /tmp/render_sepsis.html 2>/dev/null && echo "true" || echo "false")

# ================================================================
# EXPORT DATA
# ================================================================

ESCAPED_TEXT=$(json_escape "$TIDDLER_TEXT")
ESCAPED_TAGS=$(json_escape "$TIDDLER_TAGS")

# Check GUI saves
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*Active Guidelines Search" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

JSON_RESULT=$(cat << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "tiddler_exists": $TIDDLER_EXISTS,
    "tiddler_tags": "$ESCAPED_TAGS",
    "tiddler_text": "$ESCAPED_TEXT",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "behavior_empty": {
        "shows_sepsis": $EMPTY_HAS_SEPSIS,
        "shows_dka": $EMPTY_HAS_DKA,
        "shows_ami": $EMPTY_HAS_AMI,
        "shows_archived": $EMPTY_HAS_ARCHIVED
    },
    "behavior_sepsis": {
        "shows_sepsis": $SEPSIS_HAS_SEPSIS,
        "shows_dka": $SEPSIS_HAS_DKA,
        "shows_archived": $SEPSIS_HAS_ARCHIVED,
        "shows_meeting": $SEPSIS_HAS_MEETING
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/search_dashboard_result.json"

echo "Result saved to /tmp/search_dashboard_result.json"
cat /tmp/search_dashboard_result.json
echo "=== Export complete ==="