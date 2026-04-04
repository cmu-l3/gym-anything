#!/bin/bash
# Export script for CMS Page Embedded Widget task

echo "=== Exporting CMS Page Embedded Widget Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get counts
INITIAL_PAGE_COUNT=$(cat /tmp/initial_page_count 2>/dev/null || echo "0")
CURRENT_PAGE_COUNT=$(magento_query "SELECT COUNT(*) FROM cms_page" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "Page count: initial=$INITIAL_PAGE_COUNT, current=$CURRENT_PAGE_COUNT"

# Query the specific page by identifier
PAGE_DATA=$(magento_query "SELECT page_id, title, is_active FROM cms_page WHERE identifier='new-arrivals-showcase'" 2>/dev/null | tail -1)

PAGE_FOUND="false"
PAGE_ID=""
PAGE_TITLE=""
IS_ACTIVE=""

if [ -n "$PAGE_DATA" ]; then
    PAGE_FOUND="true"
    PAGE_ID=$(echo "$PAGE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    PAGE_TITLE=$(echo "$PAGE_DATA" | awk -F'\t' '{print $2}')
    IS_ACTIVE=$(echo "$PAGE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

echo "Page found: $PAGE_FOUND (ID=$PAGE_ID)"

# Get page content securely
# We retrieve content separately to handle potential special chars/length
PAGE_CONTENT=""
HAS_WIDGET_DIRECTIVE="false"
HAS_CORRECT_COUNT="false"
HAS_HEADING="false"
HAS_PARAGRAPH="false"

if [ "$PAGE_FOUND" = "true" ]; then
    # Fetch content
    PAGE_CONTENT=$(magento_query "SELECT content FROM cms_page WHERE page_id=$PAGE_ID" 2>/dev/null | tail -1)
    
    # Check for widget directive
    # Look for {{widget type="Magento\Catalog\Block\Product\Widget\NewWidget" ...}}
    if echo "$PAGE_CONTENT" | grep -Fq 'type="Magento\Catalog\Block\Product\Widget\NewWidget"'; then
        HAS_WIDGET_DIRECTIVE="true"
    fi
    
    # Check for products_count="6"
    if echo "$PAGE_CONTENT" | grep -Eq 'products_count="6"'; then
        HAS_CORRECT_COUNT="true"
    fi
    
    # Check for text content
    if echo "$PAGE_CONTENT" | grep -iq "Fresh Finds for the Season"; then
        HAS_HEADING="true"
    fi
    
    if echo "$PAGE_CONTENT" | grep -iq "Explore our latest additions"; then
        HAS_PARAGRAPH="true"
    fi
fi

echo "Content checks:"
echo "  Widget Directive: $HAS_WIDGET_DIRECTIVE"
echo "  Correct Count (6): $HAS_CORRECT_COUNT"
echo "  Heading Found: $HAS_HEADING"

# Escape strings for JSON
PAGE_TITLE_ESC=$(echo "$PAGE_TITLE" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/cms_widget_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_page_count": ${INITIAL_PAGE_COUNT:-0},
    "current_page_count": ${CURRENT_PAGE_COUNT:-0},
    "page_found": $PAGE_FOUND,
    "page_id": "${PAGE_ID:-}",
    "page_title": "$PAGE_TITLE_ESC",
    "is_active": "${IS_ACTIVE:-0}",
    "has_widget_directive": $HAS_WIDGET_DIRECTIVE,
    "has_correct_product_count": $HAS_CORRECT_COUNT,
    "has_heading": $HAS_HEADING,
    "has_paragraph": $HAS_PARAGRAPH,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/cms_widget_result.json

echo ""
cat /tmp/cms_widget_result.json
echo ""
echo "=== Export Complete ==="