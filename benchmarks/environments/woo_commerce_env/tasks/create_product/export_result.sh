#!/bin/bash
# Export script for Create Product task

echo "=== Exporting Create Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity before proceeding
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "product_found": false, "product": {}}' > /tmp/create_product_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current product count
CURRENT_COUNT=$(get_product_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")

echo "Product count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent products
echo ""
echo "=== DEBUG: Most recent products in database ==="
wc_query_headers "SELECT p.ID, pm.meta_value as sku, p.post_title, p.post_status
    FROM wp_posts p
    LEFT JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_sku'
    WHERE p.post_type = 'product'
    ORDER BY p.ID DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Track search method for logging (audit requirement)
SEARCH_METHOD="not_found"

# Check for the target product using case-insensitive SKU matching
echo "Checking for product SKU 'HLW-BRN-01' (case-insensitive)..."
PRODUCT_DATA=$(get_product_by_sku "HLW-BRN-01" 2>/dev/null)
if [ -n "$PRODUCT_DATA" ]; then
    SEARCH_METHOD="sku_exact"
fi

# If not found by exact SKU, try case-insensitive match with dashes optional
# (e.g., agent might enter "hlwbrn01" without dashes)
if [ -z "$PRODUCT_DATA" ]; then
    echo "Exact SKU match not found, trying without dashes..."
    PRODUCT_DATA=$(wc_query "SELECT p.ID, pm.meta_value as sku
        FROM wp_posts p
        JOIN wp_postmeta pm ON p.ID = pm.post_id
        WHERE p.post_type = 'product'
        AND pm.meta_key = '_sku'
        AND LOWER(REPLACE(pm.meta_value, '-', '')) = 'hlwbrn01'
        ORDER BY p.ID DESC LIMIT 1" 2>/dev/null)
    if [ -n "$PRODUCT_DATA" ]; then
        SEARCH_METHOD="sku_normalized"
        echo "WARNING: Product found via normalized SKU (fallback used)"
    fi
fi

# If not found by SKU, try by name
if [ -z "$PRODUCT_DATA" ]; then
    echo "SKU match not found, trying by product name..."
    PRODUCT_DATA=$(get_product_by_name "Handcrafted Leather Wallet" 2>/dev/null)
    if [ -n "$PRODUCT_DATA" ]; then
        SEARCH_METHOD="name_fallback"
        echo "WARNING: Product found via NAME FALLBACK - SKU may be incorrect"
        # Reformat to match SKU query output (ID, SKU)
        PRODUCT_ID_TEMP=$(echo "$PRODUCT_DATA" | cut -f1)
        PRODUCT_SKU_TEMP=$(echo "$PRODUCT_DATA" | cut -f2)
        PRODUCT_DATA="${PRODUCT_ID_TEMP}\t${PRODUCT_SKU_TEMP}"
    fi
fi

echo "Search method used: $SEARCH_METHOD"

# NOTE: No "newest entity" fallback - if the specific product is not found,
# it's reported as not found. The verifier handles this appropriately.

# Parse product data
PRODUCT_FOUND="false"
PRODUCT_ID=""
PRODUCT_SKU=""
PRODUCT_NAME=""
PRODUCT_PRICE=""
PRODUCT_CATEGORIES=""
PRODUCT_TYPE=""
PRODUCT_STATUS=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    PRODUCT_SKU=$(echo "$PRODUCT_DATA" | cut -f2)

    # Get product name, price, categories, type, and status
    PRODUCT_NAME=$(get_product_name "$PRODUCT_ID" 2>/dev/null)
    PRODUCT_PRICE=$(get_product_price "$PRODUCT_ID" 2>/dev/null)
    PRODUCT_CATEGORIES=$(get_product_categories "$PRODUCT_ID" 2>/dev/null)
    PRODUCT_TYPE=$(get_product_type "$PRODUCT_ID" 2>/dev/null)
    PRODUCT_STATUS=$(get_product_status "$PRODUCT_ID" 2>/dev/null)

    # Handle MySQL NULL values (GROUP_CONCAT returns literal "NULL" string)
    [ "$PRODUCT_CATEGORIES" = "NULL" ] && PRODUCT_CATEGORIES=""
    [ "$PRODUCT_TYPE" = "NULL" ] && PRODUCT_TYPE=""

    echo "Product found: ID=$PRODUCT_ID, SKU='$PRODUCT_SKU', Name='$PRODUCT_NAME', Price='$PRODUCT_PRICE', Categories='$PRODUCT_CATEGORIES', Type='$PRODUCT_TYPE', Status='$PRODUCT_STATUS'"
else
    echo "Product 'HLW-BRN-01' NOT found in database"
fi

# Escape special characters for JSON (handles quotes, backslashes, newlines, etc.)
PRODUCT_NAME_ESC=$(json_escape "$PRODUCT_NAME")
PRODUCT_SKU_ESC=$(json_escape "$PRODUCT_SKU")
PRODUCT_CATEGORIES_ESC=$(json_escape "$PRODUCT_CATEGORIES")
PRODUCT_TYPE_ESC=$(json_escape "$PRODUCT_TYPE")
PRODUCT_STATUS_ESC=$(json_escape "$PRODUCT_STATUS")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/create_product_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_product_count": ${INITIAL_COUNT:-0},
    "current_product_count": ${CURRENT_COUNT:-0},
    "product_found": $PRODUCT_FOUND,
    "search_method": "$SEARCH_METHOD",
    "product": {
        "id": "$PRODUCT_ID",
        "name": "$PRODUCT_NAME_ESC",
        "sku": "$PRODUCT_SKU_ESC",
        "price": "$PRODUCT_PRICE",
        "categories": "$PRODUCT_CATEGORIES_ESC",
        "type": "$PRODUCT_TYPE_ESC",
        "status": "$PRODUCT_STATUS_ESC"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_product_result.json

echo ""
cat /tmp/create_product_result.json
echo ""
echo "=== Export Complete ==="
