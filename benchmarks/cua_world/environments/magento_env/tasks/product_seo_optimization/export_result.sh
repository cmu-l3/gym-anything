#!/bin/bash
# Export script for Product SEO Optimization task

echo "=== Exporting Product SEO Optimization Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TARGET_SKU="LAPTOP-001"

# 1. Get Product ID
PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='$TARGET_SKU'" 2>/dev/null)

if [ -z "$PRODUCT_ID" ]; then
    echo "Product SKU '$TARGET_SKU' not found!"
    # Default empty JSON
    echo '{"product_found": false}' > /tmp/product_seo_result.json
    exit 0
fi

echo "Product ID: $PRODUCT_ID"

# 2. Get Attribute Values (url_key, meta_title, meta_description)
# Note: In Magento 2, these are typically varchar attributes.
# entity_type_id=4 is catalog_product

# Function to get attribute value
get_attribute_value() {
    local attr_code="$1"
    magento_query "SELECT v.value FROM catalog_product_entity_varchar v
    WHERE v.entity_id = $PRODUCT_ID
    AND v.attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='$attr_code' AND entity_type_id=4)
    AND v.store_id = 0 LIMIT 1" 2>/dev/null
}

CURRENT_URL_KEY=$(get_attribute_value "url_key")
CURRENT_META_TITLE=$(get_attribute_value "meta_title")
CURRENT_META_DESC=$(get_attribute_value "meta_description")

echo "URL Key: $CURRENT_URL_KEY"
echo "Meta Title: $CURRENT_META_TITLE"
echo "Meta Desc: $CURRENT_META_DESC"

# 3. Check for 301 Redirect
# We look for a redirect where the target path contains the new url key
# and redirect_type is 301.
REDIRECT_FOUND="false"
REDIRECT_COUNT=$(magento_query "SELECT COUNT(*) FROM url_rewrite 
    WHERE target_path LIKE '%$CURRENT_URL_KEY%' 
    AND redirect_type = 301 
    AND entity_type = 'product' 
    AND entity_id = $PRODUCT_ID" 2>/dev/null)

if [ "$REDIRECT_COUNT" -gt "0" ]; then
    REDIRECT_FOUND="true"
fi

# Also check simply if ANY redirect points to the new key, in case entity link is loose
if [ "$REDIRECT_FOUND" = "false" ] && [ -n "$CURRENT_URL_KEY" ]; then
    ANY_REDIRECT=$(magento_query "SELECT COUNT(*) FROM url_rewrite 
        WHERE target_path LIKE '%$CURRENT_URL_KEY%' 
        AND redirect_type = 301" 2>/dev/null)
    if [ "$ANY_REDIRECT" -gt "0" ]; then
        REDIRECT_FOUND="true"
    fi
fi

# 4. JSON Export
# Escape strings for JSON
URL_KEY_ESC=$(echo "$CURRENT_URL_KEY" | sed 's/"/\\"/g')
META_TITLE_ESC=$(echo "$CURRENT_META_TITLE" | sed 's/"/\\"/g')
META_DESC_ESC=$(echo "$CURRENT_META_DESC" | sed 's/"/\\"/g')
INITIAL_URL_KEY=$(cat /tmp/initial_url_key.txt 2>/dev/null | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/product_seo_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": true,
    "product_sku": "$TARGET_SKU",
    "initial_url_key": "$INITIAL_URL_KEY",
    "current_url_key": "$URL_KEY_ESC",
    "current_meta_title": "$META_TITLE_ESC",
    "current_meta_description": "$META_DESC_ESC",
    "redirect_found": $REDIRECT_FOUND,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/product_seo_result.json

echo ""
cat /tmp/product_seo_result.json
echo ""
echo "=== Export Complete ==="