#!/bin/bash
# Export script for create_research_guide task (post_task hook)

echo "=== Exporting create_research_guide result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial count
INITIAL_PAGE_COUNT=$(cat /tmp/initial_page_count 2>/dev/null || echo "0")

# Get current count
CURRENT_PAGE_COUNT=$(wp_cli post list --post_type=page --post_status=publish --format=count --allow-root 2>/dev/null || echo "0")

echo "Initial page count: $INITIAL_PAGE_COUNT"
echo "Current page count: $CURRENT_PAGE_COUNT"

# =============================================================================
# VERIFY PARENT PAGE
# =============================================================================
PARENT_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('Digital Humanities Research Guide') AND post_type='page' AND post_status='publish' ORDER BY ID DESC LIMIT 1" | tr -d '\n\r')

PARENT_FOUND="false"
PARENT_HAS_PHRASE="false"

if [ -n "$PARENT_ID" ] && [ "$PARENT_ID" != "0" ]; then
    PARENT_FOUND="true"
    echo "Parent page found (ID: $PARENT_ID)"
    
    # Check for content phrase using SQL LIKE to avoid bash string escaping nightmares
    MATCH=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE ID=$PARENT_ID AND LOWER(post_content) LIKE LOWER('%digital humanities resources available to researchers%')" | tr -d '\n\r')
    if [ "$MATCH" -gt 0 ]; then
        PARENT_HAS_PHRASE="true"
        echo "  - Parent contains required phrase"
    else
        echo "  - Parent MISSING required phrase"
    fi
else
    PARENT_ID=0
    echo "Parent page NOT found"
fi

# =============================================================================
# VERIFY CHILD PAGES (Helper Function)
# =============================================================================
get_child_json() {
    local title="$1"
    local expected_phrase="$2"
    
    local child_id=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('$title') AND post_type='page' AND post_status='publish' ORDER BY ID DESC LIMIT 1" | tr -d '\n\r')
    
    if [ -z "$child_id" ] || [ "$child_id" = "0" ]; then
        echo "{\"found\": false, \"id\": 0, \"parent_id\": 0, \"menu_order\": 0, \"has_phrase\": false}"
        return
    fi
    
    local parent_id=$(wp_db_query "SELECT post_parent FROM wp_posts WHERE ID=$child_id" | tr -d '\n\r')
    local menu_order=$(wp_db_query "SELECT menu_order FROM wp_posts WHERE ID=$child_id" | tr -d '\n\r')
    
    local has_phrase="false"
    local match=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE ID=$child_id AND LOWER(post_content) LIKE LOWER('%$expected_phrase%')" | tr -d '\n\r')
    
    if [ "$match" -gt 0 ]; then
        has_phrase="true"
    fi
    
    # Sanitize outputs just in case
    parent_id=${parent_id:-0}
    menu_order=${menu_order:-0}
    
    echo "{\"found\": true, \"id\": $child_id, \"parent_id\": $parent_id, \"menu_order\": $menu_order, \"has_phrase\": $has_phrase}"
}

echo "Checking child pages..."
CHILD1_JSON=$(get_child_json "Getting Started with Digital Humanities" "introduction to the field of digital humanities")
CHILD2_JSON=$(get_child_json "Primary Source Databases" "primary source collections and archival databases")
CHILD3_JSON=$(get_child_json "Digital Tools and Software" "computational tools and software platforms")
CHILD4_JSON=$(get_child_json "Citation and Attribution Guide" "proper citation practices and attribution standards")

# =============================================================================
# CREATE JSON OUTPUT
# =============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_page_count": $INITIAL_PAGE_COUNT,
    "current_page_count": $CURRENT_PAGE_COUNT,
    "parent": {
        "found": $PARENT_FOUND,
        "id": $PARENT_ID,
        "has_phrase": $PARENT_HAS_PHRASE
    },
    "children": {
        "child1": $CHILD1_JSON,
        "child2": $CHILD2_JSON,
        "child3": $CHILD3_JSON,
        "child4": $CHILD4_JSON
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to destination
rm -f /tmp/create_research_guide_result.json 2>/dev/null || sudo rm -f /tmp/create_research_guide_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_research_guide_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_research_guide_result.json
chmod 666 /tmp/create_research_guide_result.json 2>/dev/null || sudo chmod 666 /tmp/create_research_guide_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/create_research_guide_result.json"
cat /tmp/create_research_guide_result.json
echo ""
echo "=== Export complete ==="