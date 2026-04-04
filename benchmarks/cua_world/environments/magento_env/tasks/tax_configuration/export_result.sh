#!/bin/bash
# Export script for Tax Configuration task

echo "=== Exporting Tax Configuration Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_TAX_CLASS_COUNT=$(cat /tmp/initial_tax_class_count 2>/dev/null || echo "0")
INITIAL_TAX_RATE_COUNT=$(cat /tmp/initial_tax_rate_count 2>/dev/null || echo "0")
INITIAL_TAX_RULE_COUNT=$(cat /tmp/initial_tax_rule_count 2>/dev/null || echo "0")
CA_REGION_ID=$(cat /tmp/ca_region_id 2>/dev/null | tr -d '[:space:]' || echo "0")
NY_REGION_ID=$(cat /tmp/ny_region_id 2>/dev/null | tr -d '[:space:]' || echo "0")

# ── Find the Industrial Machinery product tax class ───────────────────────────
TAX_CLASS_DATA=$(magento_query "SELECT class_id, class_name, class_type FROM tax_class WHERE LOWER(TRIM(class_name)) LIKE '%industrial%machin%' AND class_type='PRODUCT' LIMIT 1" 2>/dev/null | tail -1)
TAX_CLASS_ID=$(echo "$TAX_CLASS_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
TAX_CLASS_NAME=$(echo "$TAX_CLASS_DATA" | awk -F'\t' '{print $2}')
TAX_CLASS_TYPE=$(echo "$TAX_CLASS_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')

TAX_CLASS_FOUND="false"
[ -n "$TAX_CLASS_ID" ] && TAX_CLASS_FOUND="true"
echo "Tax class: ID=$TAX_CLASS_ID name='$TAX_CLASS_NAME' type=$TAX_CLASS_TYPE found=$TAX_CLASS_FOUND"

# ── Find California tax rate ──────────────────────────────────────────────────
# Try by name first, then by region_id
CA_RATE_DATA=$(magento_query "SELECT tax_calculation_rate_id, code, rate, tax_country_id, tax_region_id, tax_postcode FROM tax_calculation_rate WHERE LOWER(TRIM(code)) LIKE '%california%' AND tax_country_id='US' ORDER BY tax_calculation_rate_id DESC LIMIT 1" 2>/dev/null | tail -1)
if [ -z "$(echo "$CA_RATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')" ] && [ "$CA_REGION_ID" != "0" ]; then
    CA_RATE_DATA=$(magento_query "SELECT tax_calculation_rate_id, code, rate, tax_country_id, tax_region_id, tax_postcode FROM tax_calculation_rate WHERE tax_region_id=$CA_REGION_ID AND tax_country_id='US' ORDER BY tax_calculation_rate_id DESC LIMIT 1" 2>/dev/null | tail -1)
fi

CA_RATE_ID=$(echo "$CA_RATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
CA_RATE_CODE=$(echo "$CA_RATE_DATA" | awk -F'\t' '{print $2}')
CA_RATE=$(echo "$CA_RATE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')

CA_RATE_FOUND="false"
[ -n "$CA_RATE_ID" ] && CA_RATE_FOUND="true"
echo "CA rate: ID=$CA_RATE_ID code='$CA_RATE_CODE' rate=$CA_RATE found=$CA_RATE_FOUND"

# ── Find New York tax rate ────────────────────────────────────────────────────
NY_RATE_DATA=$(magento_query "SELECT tax_calculation_rate_id, code, rate, tax_country_id, tax_region_id, tax_postcode FROM tax_calculation_rate WHERE LOWER(TRIM(code)) LIKE '%new york%' AND tax_country_id='US' ORDER BY tax_calculation_rate_id DESC LIMIT 1" 2>/dev/null | tail -1)
if [ -z "$(echo "$NY_RATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')" ] && [ "$NY_REGION_ID" != "0" ]; then
    NY_RATE_DATA=$(magento_query "SELECT tax_calculation_rate_id, code, rate, tax_country_id, tax_region_id, tax_postcode FROM tax_calculation_rate WHERE tax_region_id=$NY_REGION_ID AND tax_country_id='US' ORDER BY tax_calculation_rate_id DESC LIMIT 1" 2>/dev/null | tail -1)
fi

NY_RATE_ID=$(echo "$NY_RATE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
NY_RATE_CODE=$(echo "$NY_RATE_DATA" | awk -F'\t' '{print $2}')
NY_RATE=$(echo "$NY_RATE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')

NY_RATE_FOUND="false"
[ -n "$NY_RATE_ID" ] && NY_RATE_FOUND="true"
echo "NY rate: ID=$NY_RATE_ID code='$NY_RATE_CODE' rate=$NY_RATE found=$NY_RATE_FOUND"

# ── Find the tax rule ─────────────────────────────────────────────────────────
RULE_DATA=$(magento_query "SELECT tax_calculation_rule_id, code, priority FROM tax_calculation_rule WHERE LOWER(TRIM(code)) LIKE '%industrial%' ORDER BY tax_calculation_rule_id DESC LIMIT 1" 2>/dev/null | tail -1)
RULE_ID=$(echo "$RULE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
RULE_CODE=$(echo "$RULE_DATA" | awk -F'\t' '{print $2}')
RULE_PRIORITY=$(echo "$RULE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')

RULE_FOUND="false"
[ -n "$RULE_ID" ] && RULE_FOUND="true"
echo "Tax rule: ID=$RULE_ID code='$RULE_CODE' priority=$RULE_PRIORITY found=$RULE_FOUND"

# ── Check that rule links to our product tax class ───────────────────────────
RULE_LINKS_PRODUCT_CLASS="false"
RULE_LINKS_CA_RATE="false"
RULE_LINKS_NY_RATE="false"
RULE_LINKED_RATE_COUNT="0"
if [ -n "$RULE_ID" ]; then
    # Check product tax class linkage via tax_calculation
    if [ -n "$TAX_CLASS_ID" ]; then
        CLASS_LINK=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND product_tax_class_id=$TAX_CLASS_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
        [ "${CLASS_LINK:-0}" -gt "0" ] 2>/dev/null && RULE_LINKS_PRODUCT_CLASS="true"
    fi

    # Check CA rate linkage
    if [ -n "$CA_RATE_ID" ]; then
        CA_LINK=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND tax_calculation_rate_id=$CA_RATE_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
        [ "${CA_LINK:-0}" -gt "0" ] 2>/dev/null && RULE_LINKS_CA_RATE="true"
    fi

    # Check NY rate linkage
    if [ -n "$NY_RATE_ID" ]; then
        NY_LINK=$(magento_query "SELECT COUNT(*) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID AND tax_calculation_rate_id=$NY_RATE_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
        [ "${NY_LINK:-0}" -gt "0" ] 2>/dev/null && RULE_LINKS_NY_RATE="true"
    fi

    # Count distinct rates in the rule
    RULE_LINKED_RATE_COUNT=$(magento_query "SELECT COUNT(DISTINCT tax_calculation_rate_id) FROM tax_calculation WHERE tax_calculation_rule_id=$RULE_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
fi
echo "Rule links: product_class=$RULE_LINKS_PRODUCT_CLASS ca_rate=$RULE_LINKS_CA_RATE ny_rate=$RULE_LINKS_NY_RATE rate_count=$RULE_LINKED_RATE_COUNT"

# Escape for JSON
CA_RATE_CODE_ESC=$(echo "$CA_RATE_CODE" | sed 's/"/\\"/g')
NY_RATE_CODE_ESC=$(echo "$NY_RATE_CODE" | sed 's/"/\\"/g')
TAX_CLASS_NAME_ESC=$(echo "$TAX_CLASS_NAME" | sed 's/"/\\"/g')
RULE_CODE_ESC=$(echo "$RULE_CODE" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/tax_configuration_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_tax_class_count": ${INITIAL_TAX_CLASS_COUNT:-0},
    "initial_tax_rate_count": ${INITIAL_TAX_RATE_COUNT:-0},
    "initial_tax_rule_count": ${INITIAL_TAX_RULE_COUNT:-0},
    "tax_class_found": $TAX_CLASS_FOUND,
    "tax_class_id": "${TAX_CLASS_ID:-}",
    "tax_class_name": "$TAX_CLASS_NAME_ESC",
    "tax_class_type": "${TAX_CLASS_TYPE:-}",
    "ca_rate_found": $CA_RATE_FOUND,
    "ca_rate_id": "${CA_RATE_ID:-}",
    "ca_rate_code": "$CA_RATE_CODE_ESC",
    "ca_rate_percent": "${CA_RATE:-}",
    "ny_rate_found": $NY_RATE_FOUND,
    "ny_rate_id": "${NY_RATE_ID:-}",
    "ny_rate_code": "$NY_RATE_CODE_ESC",
    "ny_rate_percent": "${NY_RATE:-}",
    "rule_found": $RULE_FOUND,
    "rule_id": "${RULE_ID:-}",
    "rule_code": "$RULE_CODE_ESC",
    "rule_priority": "${RULE_PRIORITY:-}",
    "rule_links_product_class": $RULE_LINKS_PRODUCT_CLASS,
    "rule_links_ca_rate": $RULE_LINKS_CA_RATE,
    "rule_links_ny_rate": $RULE_LINKS_NY_RATE,
    "rule_linked_rate_count": ${RULE_LINKED_RATE_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/tax_configuration_result.json
echo ""
cat /tmp/tax_configuration_result.json
echo ""
echo "=== Export Complete ==="
