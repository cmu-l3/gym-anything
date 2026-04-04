#!/bin/bash
# Export script for Catalog UX/SEO Setup task

echo "=== Exporting Catalog UX/SEO Setup Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the core_config_data table for the specific paths we care about
# We look for scope='default' (scope_id=0) which is what System Configuration saves to by default
echo "Querying database for configuration..."

# 1. List Mode (catalog/frontend/list_mode)
LIST_MODE=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/frontend/list_mode' AND scope='default' LIMIT 1" 2>/dev/null)

# 2. Grid Per Page Values (catalog/frontend/grid_per_page_values)
GRID_VALUES=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/frontend/grid_per_page_values' AND scope='default' LIMIT 1" 2>/dev/null)

# 3. Grid Default Page (catalog/frontend/grid_per_page)
GRID_DEFAULT=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/frontend/grid_per_page' AND scope='default' LIMIT 1" 2>/dev/null)

# 4. Sort By (catalog/frontend/default_sort_by)
SORT_BY=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/frontend/default_sort_by' AND scope='default' LIMIT 1" 2>/dev/null)

# 5. Canonical Category (catalog/seo/category_canonical_tag)
CANONICAL_CAT=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/seo/category_canonical_tag' AND scope='default' LIMIT 1" 2>/dev/null)

# 6. Canonical Product (catalog/seo/product_canonical_tag)
CANONICAL_PROD=$(magento_query "SELECT value FROM core_config_data WHERE path='catalog/seo/product_canonical_tag' AND scope='default' LIMIT 1" 2>/dev/null)

echo "Retrieved Values:"
echo "  list_mode: $LIST_MODE"
echo "  grid_values: $GRID_VALUES"
echo "  grid_default: $GRID_DEFAULT"
echo "  sort_by: $SORT_BY"
echo "  canonical_cat: $CANONICAL_CAT"
echo "  canonical_prod: $CANONICAL_PROD"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/catalog_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "list_mode": "${LIST_MODE:-}",
    "grid_per_page_values": "${GRID_VALUES:-}",
    "grid_per_page": "${GRID_DEFAULT:-}",
    "default_sort_by": "${SORT_BY:-}",
    "category_canonical_tag": "${CANONICAL_CAT:-}",
    "product_canonical_tag": "${CANONICAL_PROD:-}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/catalog_config_result.json

echo ""
cat /tmp/catalog_config_result.json
echo ""
echo "=== Export Complete ==="