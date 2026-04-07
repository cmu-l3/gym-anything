#!/bin/bash
# Export script for Seasonal Product Launch & Fulfillment task

echo "=== Exporting Seasonal Product Launch Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# Read initial counts
INITIAL_ATTR_COUNT=$(cat /tmp/initial_attr_count 2>/dev/null || echo "0")
INITIAL_PRODUCT_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")
INITIAL_LINK_COUNT=$(cat /tmp/initial_link_count 2>/dev/null || echo "0")
INITIAL_RULE_COUNT=$(cat /tmp/initial_rule_count 2>/dev/null || echo "0")
INITIAL_COUPON_COUNT=$(cat /tmp/initial_coupon_count 2>/dev/null || echo "0")
INITIAL_ORDER_COUNT=$(cat /tmp/initial_order_count 2>/dev/null || echo "0")
INITIAL_INVOICE_COUNT=$(cat /tmp/initial_invoice_count 2>/dev/null || echo "0")
INITIAL_SHIPMENT_COUNT=$(cat /tmp/initial_shipment_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# 1. VERIFY ATTRIBUTE ('shirt_size')
# ==============================================================================
echo "Checking attribute 'shirt_size'..."
ATTR_DATA=$(magento_query "SELECT attribute_id, frontend_input, is_user_defined FROM eav_attribute WHERE attribute_code='shirt_size' AND entity_type_id=4" 2>/dev/null | tail -1)
ATTR_ID=$(echo "$ATTR_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
ATTR_INPUT=$(echo "$ATTR_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

ATTR_FOUND="false"
[ -n "$ATTR_ID" ] && ATTR_FOUND="true"

# Check options (S, M, L, XL)
OPTIONS_FOUND_COUNT=0
OPTIONS_LIST=""
if [ -n "$ATTR_ID" ]; then
    RAW_OPTIONS=$(magento_query "SELECT v.value FROM eav_attribute_option_value v
        JOIN eav_attribute_option o ON v.option_id = o.option_id
        WHERE o.attribute_id = $ATTR_ID AND v.store_id = 0" 2>/dev/null)

    OPTIONS_LIST=$(echo "$RAW_OPTIONS" | tr '\n' ',' | sed 's/,$//')

    if echo "$RAW_OPTIONS" | grep -qx "S"; then ((OPTIONS_FOUND_COUNT++)); fi
    if echo "$RAW_OPTIONS" | grep -qx "M"; then ((OPTIONS_FOUND_COUNT++)); fi
    if echo "$RAW_OPTIONS" | grep -qx "L"; then ((OPTIONS_FOUND_COUNT++)); fi
    if echo "$RAW_OPTIONS" | grep -qx "XL"; then ((OPTIONS_FOUND_COUNT++)); fi
fi

echo "Attribute: Found=$ATTR_FOUND ID=$ATTR_ID Input=$ATTR_INPUT Options=[$OPTIONS_LIST] Count=$OPTIONS_FOUND_COUNT"

# ==============================================================================
# 2. VERIFY CONFIGURABLE PRODUCT ('SHIRT-LINEN-001')
# ==============================================================================
echo "Checking product 'SHIRT-LINEN-001'..."
PROD_DATA=$(magento_query "SELECT entity_id, type_id, sku FROM catalog_product_entity WHERE LOWER(TRIM(sku))='shirt-linen-001'" 2>/dev/null | tail -1)
PROD_ID=$(echo "$PROD_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
PROD_TYPE=$(echo "$PROD_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
PROD_SKU=$(echo "$PROD_DATA" | awk -F'\t' '{print $3}')

PROD_FOUND="false"
[ -n "$PROD_ID" ] && PROD_FOUND="true"

PROD_NAME=""
PROD_PRICE=""
if [ -n "$PROD_ID" ]; then
    PROD_NAME=$(get_product_name "$PROD_ID" 2>/dev/null)
    PROD_PRICE=$(get_product_price "$PROD_ID" 2>/dev/null)
fi

# Check category assignment
PROD_CATEGORY=""
if [ -n "$PROD_ID" ]; then
    CLOTHING_CAT_ID=$(magento_query "SELECT entity_id FROM catalog_category_entity_varchar
        WHERE value = 'Clothing'
        AND attribute_id = (SELECT attribute_id FROM eav_attribute WHERE attribute_code='name' AND entity_type_id=3)
        LIMIT 1" 2>/dev/null | tail -1)

    if [ -n "$CLOTHING_CAT_ID" ]; then
        IS_IN_CAT=$(magento_query "SELECT COUNT(*) FROM catalog_category_product WHERE product_id=$PROD_ID AND category_id=$CLOTHING_CAT_ID" 2>/dev/null | tail -1)
        [ "$IS_IN_CAT" -gt "0" ] && PROD_CATEGORY="Clothing"
    fi
fi

echo "Product: Found=$PROD_FOUND Type=$PROD_TYPE Name='$PROD_NAME' Price=$PROD_PRICE Category='$PROD_CATEGORY'"

# ==============================================================================
# 3. VERIFY VARIANTS
# ==============================================================================
VARIANT_COUNT=0
VARIANT_QTY_OK=0
if [ -n "$PROD_ID" ]; then
    VARIANT_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_super_link WHERE parent_id=$PROD_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

    # Check stock quantities for linked variants
    if [ "$VARIANT_COUNT" -gt "0" ]; then
        VARIANT_QTY_OK=$(magento_query "SELECT COUNT(*) FROM cataloginventory_stock_item si
            JOIN catalog_product_super_link sl ON si.product_id = sl.product_id
            WHERE sl.parent_id=$PROD_ID AND si.qty >= 45 AND si.qty <= 55" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
    fi
fi
echo "Variants linked: $VARIANT_COUNT, with correct qty: $VARIANT_QTY_OK"

# ==============================================================================
# 4. VERIFY CART PRICE RULE
# ==============================================================================
echo "Checking cart price rule 'Summer Checkout Bonus'..."
RULE_DATA=$(magento_query "SELECT rule_id, name, is_active, simple_action, discount_amount, uses_per_coupon, uses_per_customer, coupon_type FROM salesrule WHERE LOWER(name) LIKE '%summer checkout bonus%' ORDER BY rule_id DESC LIMIT 1" 2>/dev/null | tail -1)

RULE_ID=$(echo "$RULE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
RULE_NAME=$(echo "$RULE_DATA" | awk -F'\t' '{print $2}')
RULE_ACTIVE=$(echo "$RULE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
DISCOUNT_TYPE=$(echo "$RULE_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
DISCOUNT_AMOUNT=$(echo "$RULE_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
USES_PER_COUPON=$(echo "$RULE_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
USES_PER_CUSTOMER=$(echo "$RULE_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')
COUPON_TYPE=$(echo "$RULE_DATA" | awk -F'\t' '{print $8}' | tr -d '[:space:]')

RULE_FOUND="false"
[ -n "$RULE_ID" ] && RULE_FOUND="true"

echo "Rule: Found=$RULE_FOUND Active=$RULE_ACTIVE Type=$DISCOUNT_TYPE Amount=$DISCOUNT_AMOUNT"

# Check coupon code SUMMER25
COUPON_FOUND="false"
COUPON_USAGE_LIMIT=""
if [ -n "$RULE_ID" ]; then
    COUPON_DATA=$(magento_query "SELECT coupon_id, usage_limit FROM salesrule_coupon WHERE UPPER(code)='SUMMER25' AND rule_id=$RULE_ID" 2>/dev/null | tail -1)
    COUPON_ID=$(echo "$COUPON_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    COUPON_USAGE_LIMIT=$(echo "$COUPON_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    [ -n "$COUPON_ID" ] && COUPON_FOUND="true"
fi

echo "Coupon SUMMER25: Found=$COUPON_FOUND UsageLimit=$COUPON_USAGE_LIMIT"

# Check subtotal condition
HAS_SUBTOTAL_CONDITION="false"
SUBTOTAL_VALUE=""
if [ -n "$RULE_ID" ]; then
    CONDITIONS_RAW=$(magento_query "SELECT conditions_serialized FROM salesrule WHERE rule_id=$RULE_ID" 2>/dev/null | tail -1 || echo "")
    if echo "$CONDITIONS_RAW" | grep -qi "base_subtotal"; then
        HAS_SUBTOTAL_CONDITION="true"
        if echo "$CONDITIONS_RAW" | grep -qi '"200"\|"200.0"\|value.*200'; then
            SUBTOTAL_VALUE="200"
        fi
    fi
fi

# ==============================================================================
# 5. VERIFY ORDER
# ==============================================================================
echo "Checking order for john.doe@example.com..."
TARGET_EMAIL="john.doe@example.com"

ORDER_DATA=$(magento_query "SELECT entity_id, increment_id, grand_total, status, customer_email, coupon_code, created_at FROM sales_order WHERE customer_email='$TARGET_EMAIL' AND created_at >= FROM_UNIXTIME($TASK_START_TIME) ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1)

ORDER_FOUND="false"
ORDER_ID=""
ORDER_INCREMENT=""
ORDER_TOTAL=""
ORDER_STATUS=""
ORDER_COUPON=""

if [ -n "$ORDER_DATA" ]; then
    ORDER_FOUND="true"
    ORDER_ID=$(echo "$ORDER_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    ORDER_INCREMENT=$(echo "$ORDER_DATA" | awk -F'\t' '{print $2}')
    ORDER_TOTAL=$(echo "$ORDER_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    ORDER_STATUS=$(echo "$ORDER_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    ORDER_COUPON=$(echo "$ORDER_DATA" | awk -F'\t' '{print $6}')
fi

echo "Order: Found=$ORDER_FOUND ID=$ORDER_ID Status=$ORDER_STATUS Coupon=$ORDER_COUPON"

# Get order items
ITEMS_JSON="[]"
HAS_SHIRT="false"
HAS_JACKET="false"
if [ "$ORDER_FOUND" = "true" ]; then
    ITEMS_RAW=$(magento_query "SELECT sku, qty_ordered, price FROM sales_order_item WHERE order_id=$ORDER_ID AND parent_item_id IS NULL" 2>/dev/null)

    if [ -n "$ITEMS_RAW" ]; then
        ITEMS_JSON=$(echo "$ITEMS_RAW" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(split("\t")) | map({"sku": .[0], "qty": .[1], "price": .[2]})')
        echo "$ITEMS_RAW" | grep -qi "shirt-linen" && HAS_SHIRT="true"
        echo "$ITEMS_RAW" | grep -qi "jacket-001" && HAS_JACKET="true"
    fi
fi

# Get shipping address
ADDRESS_JSON="{}"
if [ "$ORDER_FOUND" = "true" ]; then
    ADDR_RAW=$(magento_query "SELECT firstname, lastname, city, region, postcode, street, telephone FROM sales_order_address WHERE parent_id=$ORDER_ID AND address_type='shipping' LIMIT 1" 2>/dev/null | tail -1)

    if [ -n "$ADDR_RAW" ]; then
        FIRST=$(echo "$ADDR_RAW" | awk -F'\t' '{print $1}')
        LAST=$(echo "$ADDR_RAW" | awk -F'\t' '{print $2}')
        CITY=$(echo "$ADDR_RAW" | awk -F'\t' '{print $3}')
        REGION=$(echo "$ADDR_RAW" | awk -F'\t' '{print $4}')
        POSTCODE=$(echo "$ADDR_RAW" | awk -F'\t' '{print $5}')

        ADDRESS_JSON=$(jq -n \
            --arg first "$FIRST" \
            --arg last "$LAST" \
            --arg city "$CITY" \
            --arg region "$REGION" \
            --arg zip "$POSTCODE" \
            '{"firstname": $first, "lastname": $last, "city": $city, "region": $region, "postcode": $zip}')
    fi
fi

# Get payment method
PAYMENT_METHOD=""
if [ "$ORDER_FOUND" = "true" ]; then
    PAYMENT_METHOD=$(magento_query "SELECT method FROM sales_order_payment WHERE parent_id=$ORDER_ID LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
fi

# ==============================================================================
# 6. VERIFY INVOICE
# ==============================================================================
INVOICE_FOUND="false"
if [ "$ORDER_FOUND" = "true" ]; then
    INVOICE_ID=$(magento_query "SELECT entity_id FROM sales_invoice WHERE order_id=$ORDER_ID LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
    [ -n "$INVOICE_ID" ] && INVOICE_FOUND="true"
fi
echo "Invoice: Found=$INVOICE_FOUND"

# ==============================================================================
# 7. VERIFY SHIPMENT + TRACKING
# ==============================================================================
SHIPMENT_FOUND="false"
TRACKING_NUMBER=""
if [ "$ORDER_FOUND" = "true" ]; then
    SHIPMENT_ID=$(magento_query "SELECT entity_id FROM sales_shipment WHERE order_id=$ORDER_ID LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [ -n "$SHIPMENT_ID" ]; then
        SHIPMENT_FOUND="true"
        TRACKING_NUMBER=$(magento_query "SELECT track_number FROM sales_shipment_track WHERE parent_id=$SHIPMENT_ID LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
    fi
fi
echo "Shipment: Found=$SHIPMENT_FOUND Tracking=$TRACKING_NUMBER"

# ==============================================================================
# 8. EXPORT JSON
# ==============================================================================

PROD_NAME_ESC=$(echo "$PROD_NAME" | sed 's/"/\\"/g')
PROD_SKU_ESC=$(echo "$PROD_SKU" | sed 's/"/\\"/g')
OPTIONS_LIST_ESC=$(echo "$OPTIONS_LIST" | sed 's/"/\\"/g')
RULE_NAME_ESC=$(echo "$RULE_NAME" | sed 's/"/\\"/g')
ORDER_COUPON_ESC=$(echo "$ORDER_COUPON" | sed 's/"/\\"/g' | tr -d '[:space:]')

TEMP_JSON=$(mktemp /tmp/seasonal_launch_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,

    "attribute_found": $ATTR_FOUND,
    "attribute_id": "${ATTR_ID:-}",
    "attribute_input": "${ATTR_INPUT:-}",
    "options_found_count": ${OPTIONS_FOUND_COUNT:-0},
    "options_list": "$OPTIONS_LIST_ESC",

    "product_found": $PROD_FOUND,
    "product_id": "${PROD_ID:-}",
    "product_type": "${PROD_TYPE:-}",
    "product_sku": "$PROD_SKU_ESC",
    "product_name": "$PROD_NAME_ESC",
    "product_price": "${PROD_PRICE:-}",
    "product_category": "${PROD_CATEGORY:-}",

    "variant_count": ${VARIANT_COUNT:-0},
    "variant_qty_ok": ${VARIANT_QTY_OK:-0},

    "rule_found": $RULE_FOUND,
    "rule_id": "${RULE_ID:-}",
    "rule_name": "$RULE_NAME_ESC",
    "rule_active": "${RULE_ACTIVE:-}",
    "discount_type": "${DISCOUNT_TYPE:-}",
    "discount_amount": "${DISCOUNT_AMOUNT:-}",
    "uses_per_customer": "${USES_PER_CUSTOMER:-}",
    "coupon_type": "${COUPON_TYPE:-}",
    "coupon_found": $COUPON_FOUND,
    "coupon_usage_limit": "${COUPON_USAGE_LIMIT:-}",
    "has_subtotal_condition": $HAS_SUBTOTAL_CONDITION,
    "subtotal_value": "${SUBTOTAL_VALUE:-}",

    "order_found": $ORDER_FOUND,
    "order_id": "${ORDER_ID:-}",
    "order_increment": "${ORDER_INCREMENT:-}",
    "order_total": "${ORDER_TOTAL:-}",
    "order_status": "${ORDER_STATUS:-}",
    "order_coupon": "$ORDER_COUPON_ESC",
    "order_has_shirt": $HAS_SHIRT,
    "order_has_jacket": $HAS_JACKET,
    "order_items": $ITEMS_JSON,
    "shipping_address": $ADDRESS_JSON,
    "payment_method": "${PAYMENT_METHOD:-}",

    "invoice_found": $INVOICE_FOUND,
    "shipment_found": $SHIPMENT_FOUND,
    "tracking_number": "${TRACKING_NUMBER:-}",

    "initial_counts": {
        "attributes": ${INITIAL_ATTR_COUNT:-0},
        "products": ${INITIAL_PRODUCT_COUNT:-0},
        "links": ${INITIAL_LINK_COUNT:-0},
        "rules": ${INITIAL_RULE_COUNT:-0},
        "coupons": ${INITIAL_COUPON_COUNT:-0},
        "orders": ${INITIAL_ORDER_COUNT:-0},
        "invoices": ${INITIAL_INVOICE_COUNT:-0},
        "shipments": ${INITIAL_SHIPMENT_COUNT:-0}
    },

    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/seasonal_launch_result.json

echo ""
cat /tmp/seasonal_launch_result.json
echo ""
echo "=== Export Complete ==="
