#!/bin/bash
# Export script for Create Coupon Campaign task
echo "=== Exporting Create Coupon Campaign Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Find the promotion
echo "Searching for promotion..."
PROMO_ROW=$(drupal_db_query "SELECT promotion_id, name, offer__target_plugin_id, status, require_coupon FROM commerce_promotion_field_data WHERE name LIKE '%Influencer Summer Campaign%' ORDER BY promotion_id DESC LIMIT 1")

PROMO_FOUND="false"
PROMO_ID=""
PROMO_NAME=""
OFFER_PLUGIN=""
PROMO_STATUS=""
REQUIRE_COUPON=""
OFFER_CONFIG_BLOB=""
CONDITION_CONFIG_BLOB=""
STORE_LINKED="false"

if [ -n "$PROMO_ROW" ]; then
    PROMO_FOUND="true"
    PROMO_ID=$(echo "$PROMO_ROW" | cut -f1)
    PROMO_NAME=$(echo "$PROMO_ROW" | cut -f2)
    OFFER_PLUGIN=$(echo "$PROMO_ROW" | cut -f3)
    PROMO_STATUS=$(echo "$PROMO_ROW" | cut -f4)
    REQUIRE_COUPON=$(echo "$PROMO_ROW" | cut -f5)
    
    # Fetch blobs separately to handle potential special chars
    OFFER_CONFIG_BLOB=$(drupal_db_query "SELECT CAST(offer__target_plugin_configuration AS CHAR) FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID")
    
    # Fetch condition blob
    CONDITION_CONFIG_BLOB=$(drupal_db_query "SELECT CAST(conditions__target_plugin_configuration AS CHAR) FROM commerce_promotion__conditions WHERE entity_id = $PROMO_ID AND conditions__target_plugin_id = 'order_total_price'")
    
    # Check store linkage
    STORE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__stores WHERE entity_id = $PROMO_ID AND stores_target_id = 1")
    if [ "$STORE_COUNT" -gt 0 ]; then
        STORE_LINKED="true"
    fi
fi

# 2. Extract values from serialized blobs using Python
# We pass the blobs via environment variables to avoid shell escaping hell
export OFFER_BLOB="$OFFER_CONFIG_BLOB"
export CONDITION_BLOB="$CONDITION_CONFIG_BLOB"

PARSED_VALUES=$(python3 -c '
import os, re, json

offer_blob = os.environ.get("OFFER_BLOB", "")
condition_blob = os.environ.get("CONDITION_BLOB", "")

# Extract percentage (look for "percentage";s:4:"0.20" or similar)
# Also handles string or double serialization types
percentage = ""
m_pct = re.search(r"percentage\";[sid]:\d*:\"?([0-9.]+)\"?", offer_blob)
if m_pct:
    percentage = m_pct.group(1)
else:
    # Fallback for simpler pattern
    m_pct_simple = re.search(r"percentage.*?([0-9.]+)", offer_blob)
    if m_pct_simple:
        percentage = m_pct_simple.group(1)

# Extract amount (look for "number";s:6:"200.00")
amount = ""
m_amt = re.search(r"number\";[sid]:\d*:\"?([0-9.]+)\"?", condition_blob)
if m_amt:
    amount = m_amt.group(1)
else:
    m_amt_simple = re.search(r"number.*?([0-9.]+)", condition_blob)
    if m_amt_simple:
        amount = m_amt_simple.group(1)

print(json.dumps({"percentage": percentage, "min_order_amount": amount}))
')

OFFER_PERCENTAGE=$(echo "$PARSED_VALUES" | jq -r .percentage)
MIN_ORDER_AMOUNT=$(echo "$PARSED_VALUES" | jq -r .min_order_amount)

# 3. Fetch Coupons
# We look for the 5 specific coupons and check if they are linked to the promotion
COUPON_RESULTS="[]"
if [ -n "$PROMO_ID" ]; then
    # We construct a JSON array of the coupons found
    # Query: Code, Usage Limit, Status, and verify link to promotion
    
    COUPON_QUERY="SELECT c.code, c.usage_limit, c.status, c.promotion_id 
                  FROM commerce_promotion_coupon c 
                  WHERE c.promotion_id = $PROMO_ID"
    
    # If explicit linking column isn't used (some versions use junction table), check junction
    # But usually commerce_promotion_coupon has promotion_id column in modern Commerce 2.x
    
    # Let's dump the coupons linked to this promo into a temp file to parse
    drupal_db_query "$COUPON_QUERY" > /tmp/coupon_dump.txt
    
    # Convert tab-separated DB dump to JSON array
    COUPON_RESULTS=$(python3 -c '
import sys, json
coupons = []
try:
    with open("/tmp/coupon_dump.txt", "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 3:
                coupons.append({
                    "code": parts[0],
                    "usage_limit": parts[1],
                    "status": parts[2],
                    "linked": True
                })
except Exception:
    pass
print(json.dumps(coupons))
')
fi

# 4. Construct Final JSON
cat > /tmp/task_result.json << EOF
{
    "promotion_found": $PROMO_FOUND,
    "promotion_id": "${PROMO_ID}",
    "promotion_name": "$(echo "$PROMO_NAME" | tr -d '\n\r')",
    "offer_plugin": "${OFFER_PLUGIN}",
    "offer_percentage": "${OFFER_PERCENTAGE}",
    "min_order_amount": "${MIN_ORDER_AMOUNT}",
    "promotion_status": "${PROMO_STATUS}",
    "require_coupon": "${REQUIRE_COUPON}",
    "store_linked": $STORE_LINKED,
    "found_coupons": $COUPON_RESULTS,
    "timestamp": "$(date +%s)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null

echo "Export complete. Result:"
cat /tmp/task_result.json