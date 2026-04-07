#!/bin/bash
echo "=== Exporting manage_customer_subscription results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query the Product
echo "--- Querying Product ---"
PRODUCT_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT row_to_json(t) FROM (
    SELECT m_product_id, value, name, producttype, uom_id, created
    FROM m_product 
    WHERE value = 'SVC-GARDEN-001' AND ad_client_id=$CLIENT_ID
) t
" 2>/dev/null || echo "null")

# 2. Query the Subscription Type
echo "--- Querying Subscription Type ---"
SUBTYPE_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT row_to_json(t) FROM (
    SELECT c_subscriptiontype_id, name, frequencytype, created
    FROM c_subscriptiontype 
    WHERE name = 'Monthly Care Plan' AND ad_client_id=$CLIENT_ID
) t
" 2>/dev/null || echo "null")

# 3. Query the Subscription (with joins to verify relationships)
echo "--- Querying Subscription ---"
SUB_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT row_to_json(t) FROM (
    SELECT 
        s.c_subscription_id,
        s.name,
        s.startdate,
        s.paiduntildate,
        s.renewaldate,
        s.created,
        bp.name as bp_name,
        p.value as product_value,
        st.name as subtype_name
    FROM c_subscription s
    LEFT JOIN c_bpartner bp ON s.c_bpartner_id = bp.c_bpartner_id
    LEFT JOIN m_product p ON s.m_product_id = p.m_product_id
    LEFT JOIN c_subscriptiontype st ON s.c_subscriptiontype_id = st.c_subscriptiontype_id
    WHERE s.name = 'C&W HQ Maintenance 2025' AND s.ad_client_id=$CLIENT_ID
) t
" 2>/dev/null || echo "null")

# Handle empty results
if [ -z "$PRODUCT_JSON" ]; then PRODUCT_JSON="null"; fi
if [ -z "$SUBTYPE_JSON" ]; then SUBTYPE_JSON="null"; fi
if [ -z "$SUB_JSON" ]; then SUB_JSON="null"; fi

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "product": $PRODUCT_JSON,
    "subscription_type": $SUBTYPE_JSON,
    "subscription": $SUB_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json

echo "=== Export complete ==="