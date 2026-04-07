#!/bin/bash
echo "=== Exporting configure_product_purchasing results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------------
# Query Database for Verification
# -----------------------------------------------------------------------------
echo "Querying iDempiere database..."

# We query for the M_Product_PO record joining Product and Business Partner
# We select relevant fields to verify the agent's work
QUERY="
SELECT 
    po.m_product_po_id,
    po.order_min,
    po.deliverytime_promised,
    po.pricelist,
    po.created,
    po.isactive
FROM m_product_po po
JOIN m_product p ON po.m_product_id = p.m_product_id
JOIN c_bpartner bp ON po.c_bpartner_id = bp.c_bpartner_id
WHERE p.name = 'Heavy Duty Tarp'
  AND bp.name = 'Industrial Supply Co'
  AND po.ad_client_id = $CLIENT_ID
ORDER BY po.created DESC
LIMIT 1
"

# Execute query using helper (returns pipe-separated values by default with -A -t in helper)
# We need to handle potential empty result if agent failed completely.
# Using a customized psql call here for JSON formatting if possible, or parsing standard output.
# Simplest is to get raw fields separated by |

RAW_RESULT=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|" -c "$QUERY" 2>/dev/null || true)

echo "Raw DB Result: $RAW_RESULT"

# Parse result
RECORD_EXISTS="false"
ORDER_MIN="0"
DELIVERY_TIME="0"
PRICE="0"
CREATED_TS=""
IS_ACTIVE="N"

if [ -n "$RAW_RESULT" ]; then
    RECORD_EXISTS="true"
    # Cut fields based on selection order
    ORDER_MIN=$(echo "$RAW_RESULT" | cut -d'|' -f2)
    DELIVERY_TIME=$(echo "$RAW_RESULT" | cut -d'|' -f3)
    PRICE=$(echo "$RAW_RESULT" | cut -d'|' -f4)
    CREATED_TS=$(echo "$RAW_RESULT" | cut -d'|' -f5)
    IS_ACTIVE=$(echo "$RAW_RESULT" | cut -d'|' -f6)
fi

# Check if application was running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# -----------------------------------------------------------------------------
# JSON Export
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_exists": $RECORD_EXISTS,
    "order_min": "$ORDER_MIN",
    "delivery_time": "$DELIVERY_TIME",
    "price": "$PRICE",
    "is_active": "$IS_ACTIVE",
    "db_created_timestamp": "$CREATED_TS",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="