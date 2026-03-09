#!/bin/bash
set -e

echo "=== Exporting create_custom_price_order result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/create_custom_price_order_end.png

USER_ID=$(drupal_db_query "SELECT uid FROM users_field_data WHERE LOWER(name) = LOWER('mikewilson') LIMIT 1" 2>/dev/null || echo "")
ORDER_ID=""
ORDER_STATE=""
ORDER_CHANGED="0"
ITEMS_JSON="[]"
MODIFIED_DURING_TASK="false"
TASK_START=$(cat /tmp/create_custom_price_order_start_ts 2>/dev/null || echo "0")

if [ -n "$USER_ID" ]; then
    ORDER_DATA=$(drupal_db_query "SELECT order_id, state, changed FROM commerce_order WHERE uid = $USER_ID ORDER BY order_id DESC LIMIT 1" 2>/dev/null || echo "")
    ORDER_ID=$(echo "$ORDER_DATA" | awk '{print $1}')
    ORDER_STATE=$(echo "$ORDER_DATA" | awk '{print $2}')
    ORDER_CHANGED=$(echo "$ORDER_DATA" | awk '{print $3}')
fi

if [ -n "$ORDER_ID" ]; then
    ITEMS_TSV=$(drupal_db_query "
SELECT v.sku, oi.title, oi.quantity, oi.unit_price__number
FROM commerce_order__order_items oi_link
JOIN commerce_order_item oi ON oi_link.order_items_target_id = oi.order_item_id
JOIN commerce_product_variation_field_data v ON oi.purchased_entity = v.variation_id
WHERE oi_link.entity_id = $ORDER_ID
ORDER BY oi.order_item_id
" 2>/dev/null || echo "")

    if [ -n "$ORDER_CHANGED" ] && [ "$ORDER_CHANGED" -gt "$TASK_START" ] 2>/dev/null; then
        MODIFIED_DURING_TASK="true"
    fi

    ITEMS_JSON=$(ITEMS_TSV="$ITEMS_TSV" python3 <<'PY'
import json
import os

rows = []
for line in os.environ.get("ITEMS_TSV", "").splitlines():
    parts = line.split("\t")
    if len(parts) < 4:
        continue
    sku, title, quantity, unit_price = parts[:4]
    try:
        quantity_val = float(quantity)
    except ValueError:
        quantity_val = 0
    rows.append(
        {
            "sku": sku.strip(),
            "title": title.strip(),
            "quantity": quantity_val,
            "unit_price": unit_price.strip(),
        }
    )
print(json.dumps(rows))
PY
)
fi

python3 <<PY
import json

data = {
    "user_id": "${USER_ID}",
    "order_id": "${ORDER_ID}",
    "order_state": "${ORDER_STATE}",
    "modified_during_task": "${MODIFIED_DURING_TASK}".lower() == "true",
    "items": json.loads("""${ITEMS_JSON}"""),
}

with open("/tmp/create_custom_price_order_result.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

chmod 666 /tmp/create_custom_price_order_result.json
cat /tmp/create_custom_price_order_result.json
echo "=== Export complete ==="
