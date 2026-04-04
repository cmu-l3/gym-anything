#!/bin/bash
# Export script for Credit Memo Refund task
set -e

echo "=== Exporting Credit Memo Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_creditmemo_count 2>/dev/null || echo "0")

# 3. Find John Smith's Order ID
ORDER_ID=$(magento_query "SELECT entity_id FROM sales_order WHERE customer_email='john.smith@example.com' ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]')
echo "Target Order ID: $ORDER_ID"

# 4. Find Credit Memo for this order created AFTER task start
# We join sales_creditmemo to verify it belongs to our order
CREDITMEMO_QUERY="SELECT entity_id, increment_id, grand_total, shipping_amount, adjustment_positive, adjustment_negative, created_at 
                  FROM sales_creditmemo 
                  WHERE order_id='$ORDER_ID' 
                  AND created_at >= FROM_UNIXTIME($TASK_START)
                  ORDER BY entity_id DESC LIMIT 1"

CM_DATA=$(magento_query "$CREDITMEMO_QUERY" 2>/dev/null | tail -1)

CM_FOUND="false"
CM_ID=""
CM_INCREMENT_ID=""
CM_TOTAL=""
CM_SHIPPING=""
CM_ADJ_POS=""
CM_ADJ_NEG=""
CM_CREATED=""

if [ -n "$CM_DATA" ]; then
    CM_FOUND="true"
    CM_ID=$(echo "$CM_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    CM_INCREMENT_ID=$(echo "$CM_DATA" | awk -F'\t' '{print $2}')
    CM_TOTAL=$(echo "$CM_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    CM_SHIPPING=$(echo "$CM_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    CM_ADJ_POS=$(echo "$CM_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
    CM_ADJ_NEG=$(echo "$CM_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
    CM_CREATED=$(echo "$CM_DATA" | awk -F'\t' '{print $7}')
fi

echo "Credit Memo Found: $CM_FOUND (ID: $CM_ID)"

# 5. Get Credit Memo Items (if found)
REFUNDED_ITEMS_JSON="[]"
if [ "$CM_FOUND" = "true" ]; then
    ITEMS_QUERY="SELECT sku, qty, price, row_total FROM sales_creditmemo_item WHERE parent_id='$CM_ID'"
    
    # We'll construct a simple JSON array manually or via python because bash JSON handling is messy
    REFUNDED_ITEMS_JSON=$(python3 -c "
import sys, pymysql, json

try:
    conn = pymysql.connect(host='127.0.0.1', user='magento', password='magentopass', database='magento', port=3306)
    cursor = conn.cursor()
    cursor.execute(\"$ITEMS_QUERY\")
    items = []
    for row in cursor.fetchall():
        items.append({
            'sku': row[0], 
            'qty': float(row[1]), 
            'price': float(row[2]),
            'row_total': float(row[3])
        })
    print(json.dumps(items))
except Exception as e:
    print('[]')
")
fi

# 6. Get Current Credit Memo Count
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_creditmemo" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

# 7. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/credit_memo_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "order_id": "${ORDER_ID:-}",
    "credit_memo_found": $CM_FOUND,
    "credit_memo": {
        "id": "${CM_ID:-}",
        "increment_id": "${CM_INCREMENT_ID:-}",
        "grand_total": "${CM_TOTAL:-0}",
        "shipping_amount": "${CM_SHIPPING:-0}",
        "adjustment_positive": "${CM_ADJ_POS:-0}",
        "adjustment_negative": "${CM_ADJ_NEG:-0}",
        "created_at": "${CM_CREATED:-}",
        "items": $REFUNDED_ITEMS_JSON
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 8. Save Result safely
safe_write_json "$TEMP_JSON" /tmp/credit_memo_result.json

echo "Result exported to /tmp/credit_memo_result.json"
cat /tmp/credit_memo_result.json
echo ""
echo "=== Export Complete ==="