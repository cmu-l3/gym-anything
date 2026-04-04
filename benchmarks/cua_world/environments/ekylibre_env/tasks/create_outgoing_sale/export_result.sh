#!/bin/bash
set -e
echo "=== Exporting task results: create_outgoing_sale ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SALES=$(cat /tmp/initial_sales_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# 1. Get current counts
CURRENT_SALES=$(ekylibre_db_query "SELECT COUNT(*) FROM sales;" 2>/dev/null || echo "0")
CURRENT_ITEMS=$(ekylibre_db_query "SELECT COUNT(*) FROM sale_items;" 2>/dev/null || echo "0")

# 2. Find the most recently created sale
# We select the one with the highest ID
LATEST_SALE_JSON=$(ekylibre_db_query "
    SELECT row_to_json(t) FROM (
        SELECT id, client_id, state, created_at, 
               EXTRACT(EPOCH FROM created_at)::bigint as created_ts
        FROM sales 
        ORDER BY id DESC 
        LIMIT 1
    ) t;
" 2>/dev/null || echo "{}")

# Extract ID from JSON for item query (simple parsing since jq might not be in db container, but is in host)
SALE_ID=$(echo "$LATEST_SALE_JSON" | grep -o '"id":[0-9]*' | cut -d':' -f2 || echo "")

# 3. Get items for this sale
ITEMS_JSON="[]"
CLIENT_NAME=""

if [ -n "$SALE_ID" ]; then
    # Get client name
    CLIENT_ID=$(echo "$LATEST_SALE_JSON" | grep -o '"client_id":[0-9]*' | cut -d':' -f2 || echo "")
    if [ -n "$CLIENT_ID" ] && [ "$CLIENT_ID" != "null" ]; then
        CLIENT_NAME=$(ekylibre_db_query "SELECT full_name FROM entities WHERE id = $CLIENT_ID;" 2>/dev/null || echo "")
    fi

    # Get items
    # We explicitly select unit_pretax_amount and quantity
    ITEMS_JSON=$(ekylibre_db_query "
        SELECT json_agg(row_to_json(t)) FROM (
            SELECT id, quantity, unit_pretax_amount, unit_amount, product_nature_variant_id
            FROM sale_items 
            WHERE sale_id = $SALE_ID
        ) t;
    " 2>/dev/null || echo "[]")
    
    # Handle empty result (if null returned)
    if [ "$ITEMS_JSON" = "" ]; then ITEMS_JSON="[]"; fi
fi

# 4. Construct Result JSON
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_sales_count": ${INITIAL_SALES:-0},
    "current_sales_count": ${CURRENT_SALES:-0},
    "latest_sale": $LATEST_SALE_JSON,
    "client_name": "$(echo $CLIENT_NAME | sed 's/"/\\"/g')",
    "sale_items": $ITEMS_JSON,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="