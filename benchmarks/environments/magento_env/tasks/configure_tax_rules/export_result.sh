#!/bin/bash
# Export script for Configure Tax Rules task

echo "=== Exporting Configure Tax Rules Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# 1. Product Tax Class Check
# --------------------------
# Verify "Physical Goods" class exists
CLASS_DATA=$(magento_query "SELECT class_id, class_name, class_type FROM tax_class WHERE LOWER(TRIM(class_name))='physical goods' AND class_type='PRODUCT' LIMIT 1" 2>/dev/null | tail -1)
CLASS_ID=$(echo "$CLASS_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
CLASS_NAME=$(echo "$CLASS_DATA" | awk -F'\t' '{print $2}')
CLASS_FOUND="false"
[ -n "$CLASS_ID" ] && CLASS_FOUND="true"

echo "Product Class: found=$CLASS_FOUND name='$CLASS_NAME' id=$CLASS_ID"

# 2. Tax Rates Check
# ------------------
# We need to find 3 specific rates
# Function to get rate info by code
get_rate_info() {
    local code="$1"
    magento_query "SELECT tax_calculation_rate_id, code, rate, tax_region_id, tax_postcode FROM tax_calculation_rate WHERE LOWER(TRIM(code))=LOWER(TRIM('$code')) LIMIT 1" 2>/dev/null | tail -1
}

# Rate 1: CA
CA_RATE_DATA=$(get_rate_info "US-CA-7.25")
CA_ID=$(echo "$CA_RATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
CA_RATE_VAL=$(echo "$CA_RATE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
[ -n "$CA_ID" ] && CA_FOUND="true" || CA_FOUND="false"

# Rate 2: NY
NY_RATE_DATA=$(get_rate_info "US-NY-8.00")
NY_ID=$(echo "$NY_RATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
NY_RATE_VAL=$(echo "$NY_RATE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
[ -n "$NY_ID" ] && NY_FOUND="true" || NY_FOUND="false"

# Rate 3: TX
TX_RATE_DATA=$(get_rate_info "US-TX-6.25")
TX_ID=$(echo "$TX_RATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
TX_RATE_VAL=$(echo "$TX_RATE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
[ -n "$TX_ID" ] && TX_FOUND="true" || TX_FOUND="false"

echo "Rates found: CA=$CA_FOUND ($CA_RATE_VAL%), NY=$NY_FOUND ($NY_RATE_VAL%), TX=$TX_FOUND ($TX_RATE_VAL%)"

# 3. Tax Rule Check
# -----------------
RULE_DATA=$(magento_query "SELECT tax_calculation_rule_id, code FROM tax_calculation_rule WHERE LOWER(TRIM(code))='us multi-state sales tax' LIMIT 1" 2>/dev/null | tail -1)
RULE_ID=$(echo "$RULE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
RULE_CODE=$(echo "$RULE_DATA" | awk -F'\t' '{print $2}')
RULE_FOUND="false"
[ -n "$RULE_ID" ] && RULE_FOUND="true"

echo "Rule found: $RULE_FOUND id=$RULE_ID code='$RULE_CODE'"

# 4. Linkage Verification
# -----------------------
# Check if the rule is linked to the rates and the product class
# We query the tax_calculation table which resolves the Many-to-Many relationships

LINK_CA="false"
LINK_NY="false"
LINK_TX="false"
LINK_PROD_CLASS="false"
LINK_CUST_CLASS="false"

if [ "$RULE_FOUND" = "true" ]; then
    # Check rate linkages
    if [ "$CA_FOUND" = "true" ]; then
        COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND tax_calculation_rate_id=$CA_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
        [ "$COUNT" -gt 0 ] && LINK_CA="true"
    fi
    if [ "$NY_FOUND" = "true" ]; then
        COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND tax_calculation_rate_id=$NY_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
        [ "$COUNT" -gt 0 ] && LINK_NY="true"
    fi
    if [ "$TX_FOUND" = "true" ]; then
        COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND tax_calculation_rate_id=$TX_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
        [ "$COUNT" -gt 0 ] && LINK_TX="true"
    fi

    # Check product class linkage
    if [ "$CLASS_FOUND" = "true" ]; then
        COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND product_tax_class_id=$CLASS_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
        [ "$COUNT" -gt 0 ] && LINK_PROD_CLASS="true"
    fi

    # Check customer class linkage (Retail Customer is usually ID 3, but let's lookup)
    CUST_CLASS_ID=$(magento_query "SELECT class_id FROM tax_class WHERE class_name='Retail Customer' AND class_type='CUSTOMER' LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [ -n "$CUST_CLASS_ID" ]; then
        COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND customer_tax_class_id=$CUST_CLASS_ID" 2>/dev/null | tail -1 | tr -d '[:space:]')
        [ "$COUNT" -gt 0 ] && LINK_CUST_CLASS="true"
    fi
fi

echo "Linkages: CA=$LINK_CA NY=$LINK_NY TX=$LINK_TX ProdClass=$LINK_PROD_CLASS CustClass=$LINK_CUST_CLASS"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/tax_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "class_found": $CLASS_FOUND,
    "class_name": "${CLASS_NAME:-}",
    "rate_ca_found": $CA_FOUND,
    "rate_ca_val": "${CA_RATE_VAL:-0}",
    "rate_ny_found": $NY_FOUND,
    "rate_ny_val": "${NY_RATE_VAL:-0}",
    "rate_tx_found": $TX_FOUND,
    "rate_tx_val": "${TX_RATE_VAL:-0}",
    "rule_found": $RULE_FOUND,
    "rule_name": "${RULE_CODE:-}",
    "link_ca": $LINK_CA,
    "link_ny": $LINK_NY,
    "link_tx": $LINK_TX,
    "link_prod_class": $LINK_PROD_CLASS,
    "link_cust_class": $LINK_CUST_CLASS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/tax_result.json
cat /tmp/tax_result.json
echo "=== Export Complete ==="