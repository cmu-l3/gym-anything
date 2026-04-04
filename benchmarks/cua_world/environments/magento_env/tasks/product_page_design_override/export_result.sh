#!/bin/bash
# Export script for Product Page Design Override task

echo "=== Exporting Product Page Design Override Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Target Product ID
PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='LAPTOP-001'" 2>/dev/null | tail -1 | tr -d '[:space:]')
PRODUCT_FOUND="false"
if [ -n "$PRODUCT_ID" ]; then
    PRODUCT_FOUND="true"
fi

# Get Final Layout Value
# page_layout attribute code
CURRENT_LAYOUT=$(magento_query "SELECT value FROM catalog_product_entity_varchar WHERE entity_id=$PRODUCT_ID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='page_layout' AND entity_type_id=4) AND store_id=0" 2>/dev/null | tail -1)

# Get Final Container Value
# options_container attribute code
CURRENT_CONTAINER=$(magento_query "SELECT value FROM catalog_product_entity_varchar WHERE entity_id=$PRODUCT_ID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='options_container' AND entity_type_id=4) AND store_id=0" 2>/dev/null | tail -1)

# Anti-gaming: Check if global layout config was changed
# (Design > Configuration > Default Store View > Layout)
# This is stored in core_config_data, path 'web/default/cms_home_page' or similar, but layout is usually theme based.
# A simpler check: Did they change another product? e.g. PHONE-001
OTHER_PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku='PHONE-001'" 2>/dev/null | tail -1 | tr -d '[:space:]')
OTHER_LAYOUT=$(magento_query "SELECT value FROM catalog_product_entity_varchar WHERE entity_id=$OTHER_PRODUCT_ID AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='page_layout' AND entity_type_id=4) AND store_id=0" 2>/dev/null | tail -1)

echo "Product ID: $PRODUCT_ID"
echo "Current Layout: $CURRENT_LAYOUT"
echo "Current Container: $CURRENT_CONTAINER"
echo "Other Product Layout: $OTHER_LAYOUT"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/design_override_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "product_found": $PRODUCT_FOUND,
    "product_id": "${PRODUCT_ID:-}",
    "current_layout": "${CURRENT_LAYOUT:-}",
    "current_container": "${CURRENT_CONTAINER:-}",
    "other_product_layout": "${OTHER_LAYOUT:-}",
    "task_start_timestamp": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "export_timestamp": "$(date +%s)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/design_override_result.json

echo ""
cat /tmp/design_override_result.json
echo ""
echo "=== Export Complete ==="