#!/bin/bash
# Export script for Wholesale Tier Pricing task

echo "=== Exporting Wholesale Tier Pricing Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# Read initial counters
INITIAL_GROUP_COUNT=$(cat /tmp/initial_group_count 2>/dev/null || echo "0")
INITIAL_TIER_PRICE_COUNT=$(cat /tmp/initial_tier_price_count 2>/dev/null || echo "0")

# 1. Check Customer Group
echo "Checking customer group..."
GROUP_DATA=$(magento_query "SELECT customer_group_id, tax_class_id FROM customer_group WHERE LOWER(TRIM(customer_group_code))='wholesale buyers'" 2>/dev/null | tail -1)
GROUP_ID=$(echo "$GROUP_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
TAX_CLASS_ID=$(echo "$GROUP_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

GROUP_FOUND="false"
[ -n "$GROUP_ID" ] && GROUP_FOUND="true"

TAX_CLASS_NAME=""
if [ -n "$TAX_CLASS_ID" ]; then
    TAX_CLASS_NAME=$(magento_query "SELECT class_name FROM tax_class WHERE class_id=$TAX_CLASS_ID" 2>/dev/null | tail -1)
fi

echo "Group: Found=$GROUP_FOUND, ID=$GROUP_ID, TaxClass=$TAX_CLASS_NAME ($TAX_CLASS_ID)"

# 2. Check Customer Assignment
echo "Checking customer assignment..."
CUSTOMER_EMAIL="john.smith@example.com"
CUSTOMER_GROUP_CHECK=$(magento_query "SELECT group_id FROM customer_entity WHERE email='$CUSTOMER_EMAIL'" 2>/dev/null | tail -1 | tr -d '[:space:]')
CUSTOMER_IN_GROUP="false"

if [ -n "$GROUP_ID" ] && [ "$CUSTOMER_GROUP_CHECK" == "$GROUP_ID" ]; then
    CUSTOMER_IN_GROUP="true"
fi
echo "Customer $CUSTOMER_EMAIL in group: $CUSTOMER_IN_GROUP (Current Group ID: $CUSTOMER_GROUP_CHECK)"

# 3. Check Tier Prices
echo "Checking tier prices..."
# We need to export all tier prices for this group to JSON for the verifier to process
# Format: sku, qty, value
TIER_PRICES_JSON="[]"

if [ -n "$GROUP_ID" ]; then
    # Helper to construct JSON array of objects
    # Query returns: sku, qty, value
    # We use python to safely format it to JSON to avoid bash string hell
    TIER_PRICES_JSON=$(python3 -c "
import subprocess
import json
import sys

cmd = \"docker exec magento-mariadb mysql -u magento -pmagentopass magento -N -B -e \\\"SELECT cpe.sku, tp.qty, tp.value FROM catalog_product_entity_tier_price tp JOIN catalog_product_entity cpe ON tp.entity_id = cpe.entity_id WHERE tp.customer_group_id=$GROUP_ID\\\"\"
try:
    output = subprocess.check_output(cmd, shell=True).decode('utf-8')
    data = []
    for line in output.strip().split('\n'):
        if not line: continue
        parts = line.split('\t')
        if len(parts) >= 3:
            data.append({
                'sku': parts[0].strip(),
                'qty': float(parts[1]),
                'value': float(parts[2])
            })
    print(json.dumps(data))
except Exception as e:
    print('[]')
")
fi
echo "Tier prices found: $(echo "$TIER_PRICES_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")"

# Current global counts for context
CURRENT_GROUP_COUNT=$(magento_query "SELECT COUNT(*) FROM customer_group" 2>/dev/null | tail -1 | tr -d '[:space:]')
CURRENT_TIER_PRICE_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_entity_tier_price" 2>/dev/null | tail -1 | tr -d '[:space:]')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/wholesale_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_group_count": ${INITIAL_GROUP_COUNT:-0},
    "current_group_count": ${CURRENT_GROUP_COUNT:-0},
    "group_found": $GROUP_FOUND,
    "group_id": "${GROUP_ID:-}",
    "tax_class_name": "${TAX_CLASS_NAME:-}",
    "customer_in_correct_group": $CUSTOMER_IN_GROUP,
    "customer_current_group_id": "${CUSTOMER_GROUP_CHECK:-}",
    "tier_prices": $TIER_PRICES_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/wholesale_result.json

echo ""
cat /tmp/wholesale_result.json
echo ""
echo "=== Export Complete ==="