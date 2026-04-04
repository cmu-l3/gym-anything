#!/bin/bash
# Export script for edit_page task (post_task hook)
# Gathers verification data and exports to JSON

echo "=== Exporting edit_page result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get page ID from setup
PAGE_ID=$(cat /tmp/about_page_id 2>/dev/null || echo "")
INITIAL_TITLE=$(cat /tmp/initial_page_title 2>/dev/null || echo "About Us")
INITIAL_MODIFIED=$(cat /tmp/initial_page_modified 2>/dev/null || echo "")

# Initialize variables
PAGE_FOUND="false"
TITLE_CHANGED="false"
CONTENT_UPDATED="false"
HAS_OUR_VALUES="false"
HAS_INNOVATION="false"
HAS_INTEGRITY="false"
HAS_EXCELLENCE="false"
PAGE_TITLE=""
PAGE_STATUS=""
PAGE_CONTENT=""
CURRENT_MODIFIED=""

# First, try to find the page by expected new title
NEW_PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('About Our Team') AND post_type='page' LIMIT 1")

if [ -n "$NEW_PAGE_ID" ]; then
    echo "Found page with new title 'About Our Team', ID: $NEW_PAGE_ID"
    PAGE_ID="$NEW_PAGE_ID"
fi

# If we have a page ID, check its current state
if [ -n "$PAGE_ID" ]; then
    PAGE_FOUND="true"
    echo "Checking page ID: $PAGE_ID"

    # Get current page data
    PAGE_TITLE=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$PAGE_ID")
    PAGE_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$PAGE_ID")
    PAGE_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$PAGE_ID")
    CURRENT_MODIFIED=$(wp_db_query "SELECT post_modified FROM wp_posts WHERE ID=$PAGE_ID")

    echo "Current title: $PAGE_TITLE"
    echo "Current status: $PAGE_STATUS"
    echo "Content length: ${#PAGE_CONTENT}"
    echo "Current modified: $CURRENT_MODIFIED"

    # Check if title was changed
    if [ "$(echo "$PAGE_TITLE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')" = "aboutourteam" ]; then
        TITLE_CHANGED="true"
        echo "Title correctly changed to 'About Our Team'"
    fi

    # Check if content was modified (compare timestamps)
    if [ "$CURRENT_MODIFIED" != "$INITIAL_MODIFIED" ] && [ -n "$CURRENT_MODIFIED" ]; then
        CONTENT_UPDATED="true"
        echo "Page content was modified"
    fi

    # Check for required keywords in content (case-insensitive)
    PAGE_CONTENT_LOWER=$(echo "$PAGE_CONTENT" | tr '[:upper:]' '[:lower:]')

    if echo "$PAGE_CONTENT_LOWER" | grep -q "our values"; then
        HAS_OUR_VALUES="true"
        echo "Found 'Our Values' in content"
    fi

    if echo "$PAGE_CONTENT_LOWER" | grep -q "innovation"; then
        HAS_INNOVATION="true"
        echo "Found 'Innovation' in content"
    fi

    if echo "$PAGE_CONTENT_LOWER" | grep -q "integrity"; then
        HAS_INTEGRITY="true"
        echo "Found 'Integrity' in content"
    fi

    if echo "$PAGE_CONTENT_LOWER" | grep -q "excellence"; then
        HAS_EXCELLENCE="true"
        echo "Found 'Excellence' in content"
    fi

    # Check for structural elements - heading format (WordPress blocks or HTML)
    # Look for h2, h3, h4 heading tags, wp:heading blocks, or ## markdown format
    # Use grep -Pzo for multiline matching or tr to collapse newlines for pattern matching
    HAS_OUR_VALUES_HEADING="false"

    # Collapse content to single line for easier pattern matching (WordPress blocks span lines)
    PAGE_CONTENT_ONELINE=$(echo "$PAGE_CONTENT" | tr '\n' ' ' | tr -s ' ')
    PAGE_CONTENT_ONELINE_LOWER=$(echo "$PAGE_CONTENT_ONELINE" | tr '[:upper:]' '[:lower:]')

    # Check for heading patterns in collapsed content
    if echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<h[2-4][^>]*>[^<]*our\s*values[^<]*</h[2-4]>' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'wp:heading' && echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'our values' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<!-- wp:heading[^>]*-->.*our\s*values.*<!-- /wp:heading -->' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qi '^##.*our values'; then
        HAS_OUR_VALUES_HEADING="true"
        echo "Found 'Our Values' as heading"
    fi

    # Check for list structure - WordPress blocks or HTML list items
    # Count list items that contain our required values
    # Use multiline-aware matching by collapsing newlines
    VALUES_IN_LIST=0

    # For each value, check if it's in a list item (using collapsed content)
    if echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<li[^>]*>[^<]*innovation[^<]*</li>' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<li[^>]*>.*innovation.*</li>' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<!-- wp:list-item[^>]*-->.*innovation.*<!-- /wp:list-item -->' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'wp:list-item' && echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'innovation'; then
        VALUES_IN_LIST=$((VALUES_IN_LIST + 1))
        echo "Found 'Innovation' in list item"
    fi
    if echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<li[^>]*>[^<]*integrity[^<]*</li>' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<li[^>]*>.*integrity.*</li>' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<!-- wp:list-item[^>]*-->.*integrity.*<!-- /wp:list-item -->' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'wp:list-item' && echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'integrity'; then
        VALUES_IN_LIST=$((VALUES_IN_LIST + 1))
        echo "Found 'Integrity' in list item"
    fi
    if echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<li[^>]*>[^<]*excellence[^<]*</li>' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<li[^>]*>.*excellence.*</li>' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -qE '<!-- wp:list-item[^>]*-->.*excellence.*<!-- /wp:list-item -->' || \
       echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'wp:list-item' && echo "$PAGE_CONTENT_ONELINE_LOWER" | grep -q 'excellence'; then
        VALUES_IN_LIST=$((VALUES_IN_LIST + 1))
        echo "Found 'Excellence' in list item"
    fi
    HAS_LIST_STRUCTURE="false"
    if [ $VALUES_IN_LIST -ge 3 ]; then
        HAS_LIST_STRUCTURE="true"
        echo "All 3 values found in list structure"
    fi
else
    echo "Page not found!"
fi

# Escape content for JSON (remove newlines, escape quotes, limit to 5000 chars)
ESCAPED_CONTENT=$(echo "$PAGE_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 5000)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "page_found": $PAGE_FOUND,
    "page_id": "${PAGE_ID:-}",
    "initial_title": "$(echo "$INITIAL_TITLE" | sed 's/"/\\"/g' | tr -d '\n')",
    "page": {
        "title": "$(echo "$PAGE_TITLE" | sed 's/"/\\"/g' | tr -d '\n')",
        "status": "${PAGE_STATUS:-}",
        "content_length": ${#PAGE_CONTENT},
        "content": "${ESCAPED_CONTENT}"
    },
    "changes": {
        "title_changed": $TITLE_CHANGED,
        "content_updated": $CONTENT_UPDATED,
        "has_our_values": $HAS_OUR_VALUES,
        "has_innovation": $HAS_INNOVATION,
        "has_integrity": $HAS_INTEGRITY,
        "has_excellence": $HAS_EXCELLENCE,
        "has_our_values_heading": $HAS_OUR_VALUES_HEADING,
        "has_list_structure": $HAS_LIST_STRUCTURE,
        "values_in_list_count": $VALUES_IN_LIST
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/edit_page_result.json 2>/dev/null || sudo rm -f /tmp/edit_page_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/edit_page_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/edit_page_result.json
chmod 666 /tmp/edit_page_result.json 2>/dev/null || sudo chmod 666 /tmp/edit_page_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/edit_page_result.json"
cat /tmp/edit_page_result.json
echo ""
echo "=== Export complete ==="
