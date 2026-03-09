#!/bin/bash
# Export script for create_stock_inventory task

echo "=== Exporting Stock Inventory Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_inventory_count.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for the created inventory
# We look for an inventory created after task start, or by name match
echo "Querying database for results..."

# Find inventory by name (case insensitive)
INVENTORY_JSON=$(ekylibre_db_query "
    WITH target_inv AS (
        SELECT id, name, achieved_at::date as date, state, created_at
        FROM inventories
        WHERE lower(name) LIKE '%year-end stock count jan 2024%'
        ORDER BY created_at DESC LIMIT 1
    )
    SELECT row_to_json(target_inv) FROM target_inv;
")

# If not found by specific name, check for ANY new inventory
if [ -z "$INVENTORY_JSON" ]; then
    echo "Target name not found, checking for any new inventory..."
    INVENTORY_JSON=$(ekylibre_db_query "
        WITH new_inv AS (
            SELECT id, name, achieved_at::date as date, state, created_at
            FROM inventories
            WHERE created_at > to_timestamp($TASK_START)
            ORDER BY created_at DESC LIMIT 1
        )
        SELECT row_to_json(new_inv) FROM new_inv;
    ")
fi

# Extract ID to check items
INVENTORY_ID=$(echo "$INVENTORY_JSON" | jq -r '.id // empty')
ITEMS_COUNT=0
ITEMS_WITH_QTY=0

if [ -n "$INVENTORY_ID" ]; then
    echo "Found inventory ID: $INVENTORY_ID"
    
    # Count items in this inventory
    ITEMS_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM inventory_items WHERE inventory_id = $INVENTORY_ID")
    
    # Count items that have a quantity set (actual_population > 0)
    ITEMS_WITH_QTY=$(ekylibre_db_query "SELECT COUNT(*) FROM inventory_items WHERE inventory_id = $INVENTORY_ID AND actual_population > 0")
fi

# Get final total count
FINAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM inventories")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "final_count": ${FINAL_COUNT:-0},
    "inventory_found": $(if [ -n "$INVENTORY_ID" ]; then echo "true"; else echo "false"; fi),
    "inventory_details": ${INVENTORY_JSON:-"{}"},
    "items_count": ${ITEMS_COUNT:-0},
    "items_with_quantity_count": ${ITEMS_WITH_QTY:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="