#!/bin/bash
set -e

echo "=== Exporting split_backordered_order result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/split_backordered_order_end.png

USER_ID=$(drupal_db_query "SELECT uid FROM users_field_data WHERE LOWER(name) = LOWER('janesmith') LIMIT 1" 2>/dev/null || echo "")
ORIGINAL_ORDER_ID=$(cat /tmp/original_order_id.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ORIGINAL_STATE=""
ORIGINAL_CHANGED="0"
ORIGINAL_SKUS=""
SPLIT_ORDER_ID=""
SPLIT_STATE=""
SPLIT_SKUS=""
MODIFIED_DURING_TASK="false"

if [ -n "$ORIGINAL_ORDER_ID" ]; then
    ORIGINAL_META=$(drupal_db_query "SELECT state, changed FROM commerce_order WHERE order_id = $ORIGINAL_ORDER_ID" 2>/dev/null || echo "")
    ORIGINAL_STATE=$(echo "$ORIGINAL_META" | awk '{print $1}')
    ORIGINAL_CHANGED=$(echo "$ORIGINAL_META" | awk '{print $2}')
    ORIGINAL_SKUS=$(drupal_db_query "
SELECT v.sku
FROM commerce_order__order_items oi_link
JOIN commerce_order_item oi ON oi_link.order_items_target_id = oi.order_item_id
JOIN commerce_product_variation_field_data v ON oi.purchased_entity = v.variation_id
WHERE oi_link.entity_id = $ORIGINAL_ORDER_ID
ORDER BY oi.order_item_id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
fi

if [ -n "$USER_ID" ]; then
    SPLIT_ORDER_META=$(drupal_db_query "
SELECT order_id, state
FROM commerce_order
WHERE uid = $USER_ID AND order_id <> $ORIGINAL_ORDER_ID
ORDER BY order_id DESC
LIMIT 1
" 2>/dev/null || echo "")
    SPLIT_ORDER_ID=$(echo "$SPLIT_ORDER_META" | awk '{print $1}')
    SPLIT_STATE=$(echo "$SPLIT_ORDER_META" | awk '{print $2}')
fi

if [ -n "$SPLIT_ORDER_ID" ]; then
    SPLIT_SKUS=$(drupal_db_query "
SELECT v.sku
FROM commerce_order__order_items oi_link
JOIN commerce_order_item oi ON oi_link.order_items_target_id = oi.order_item_id
JOIN commerce_product_variation_field_data v ON oi.purchased_entity = v.variation_id
WHERE oi_link.entity_id = $SPLIT_ORDER_ID
ORDER BY oi.order_item_id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
fi

if [ -n "$ORIGINAL_CHANGED" ] && [ "$ORIGINAL_CHANGED" -gt "$TASK_START" ] 2>/dev/null; then
    MODIFIED_DURING_TASK="true"
fi

python3 <<PY
import json

data = {
    "original_order_id": "${ORIGINAL_ORDER_ID}",
    "original_order_state": "${ORIGINAL_STATE}",
    "original_order_skus": [s for s in "${ORIGINAL_SKUS}".split(",") if s],
    "split_order_id": "${SPLIT_ORDER_ID}",
    "split_order_state": "${SPLIT_STATE}",
    "split_order_skus": [s for s in "${SPLIT_SKUS}".split(",") if s],
    "modified_during_task": "${MODIFIED_DURING_TASK}".lower() == "true",
}

with open("/tmp/split_backordered_order_result.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

chmod 666 /tmp/split_backordered_order_result.json
cat /tmp/split_backordered_order_result.json
echo "=== Export complete ==="
