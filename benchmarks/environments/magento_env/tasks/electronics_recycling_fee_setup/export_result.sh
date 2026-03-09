#!/bin/bash
# Export script for Electronics Recycling Fee task

echo "=== Exporting Electronics Recycling Fee Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if FPT is enabled in configuration
# Path: tax/weee/enable
FPT_ENABLED_VAL=$(magento_query "SELECT value FROM core_config_data WHERE path = 'tax/weee/enable'" 2>/dev/null | tail -1 | tr -d '[:space:]')
FPT_ENABLED="false"
if [ "$FPT_ENABLED_VAL" == "1" ]; then
    FPT_ENABLED="true"
fi

# 2. Check if the attribute exists and has correct input type
# Attribute code: california_ewaste_fee
# Frontend input should be 'weee' (internal code for Fixed Product Tax)
ATTR_DATA=$(magento_query "SELECT attribute_id, frontend_input, backend_type FROM eav_attribute WHERE attribute_code = 'california_ewaste_fee'" 2>/dev/null | tail -1)
ATTR_ID=$(echo "$ATTR_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
ATTR_INPUT=$(echo "$ATTR_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

ATTR_EXISTS="false"
ATTR_TYPE_CORRECT="false"
if [ -n "$ATTR_ID" ]; then
    ATTR_EXISTS="true"
    if [ "$ATTR_INPUT" == "weee" ]; then
        ATTR_TYPE_CORRECT="true"
    fi
fi

# 3. Check if attribute is assigned to Default Attribute Set (ID 4)
ATTR_IN_SET="false"
if [ -n "$ATTR_ID" ]; then
    IN_SET_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_entity_attribute WHERE attribute_set_id = 4 AND attribute_id = $ATTR_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [ "$IN_SET_COUNT" -gt "0" ]; then
        ATTR_IN_SET="true"
    fi
fi

# 4. Check if the tax value is applied to the product
# Product: LAPTOP-001
# Table: weee_tax
PRODUCT_ID=$(magento_query "SELECT entity_id FROM catalog_product_entity WHERE sku = 'LAPTOP-001'" 2>/dev/null | tail -1 | tr -d '[:space:]')
TAX_APPLIED="false"
TAX_VALUE="0"
TAX_REGION="0"
TAX_COUNTRY=""

if [ -n "$PRODUCT_ID" ] && [ -n "$ATTR_ID" ]; then
    # Get the tax entry for this product and attribute
    # We verify country is US (ID usually 'US') and region is 12 (California)
    TAX_DATA=$(magento_query "SELECT value, website_id, country, state FROM weee_tax WHERE entity_id = $PRODUCT_ID AND attribute_id = $ATTR_ID ORDER BY value_id DESC LIMIT 1" 2>/dev/null | tail -1)
    
    if [ -n "$TAX_DATA" ]; then
        TAX_APPLIED="true"
        TAX_VALUE=$(echo "$TAX_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
        TAX_COUNTRY=$(echo "$TAX_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
        TAX_REGION=$(echo "$TAX_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    fi
fi

echo "Export Stats:"
echo "FPT Enabled: $FPT_ENABLED"
echo "Attr Exists: $ATTR_EXISTS (ID: $ATTR_ID, Type: $ATTR_INPUT)"
echo "Attr In Set: $ATTR_IN_SET"
echo "Tax Applied: $TAX_APPLIED (Value: $TAX_VALUE, Region: $TAX_REGION)"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/fpt_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "fpt_enabled": $FPT_ENABLED,
    "attribute_exists": $ATTR_EXISTS,
    "attribute_type": "${ATTR_INPUT:-unknown}",
    "attribute_in_set": $ATTR_IN_SET,
    "tax_applied": $TAX_APPLIED,
    "tax_value": "${TAX_VALUE:-0}",
    "tax_region": "${TAX_REGION:-0}",
    "tax_country": "${TAX_COUNTRY:-}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/fpt_task_result.json
cat /tmp/fpt_task_result.json
echo "=== Export Complete ==="