#!/bin/bash
echo "=== Exporting create_product_catalog task ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Category info
CAT_ID=$(suitecrm_db_query "SELECT id FROM aos_products_categories WHERE name='Industrial Sensors' AND deleted=0 LIMIT 1" | tr -d '[:space:]')
CAT_DESC=$(suitecrm_db_query "SELECT description FROM aos_products_categories WHERE name='Industrial Sensors' AND deleted=0 LIMIT 1" | tr -d '\n' | sed 's/"/\\"/g' | sed 's/\t/ /g')
CAT_TS=$(suitecrm_db_query "SELECT UNIX_TIMESTAMP(date_entered) FROM aos_products_categories WHERE name='Industrial Sensors' AND deleted=0 LIMIT 1" | tr -d '[:space:]')

# Product 1 info
P1_DATA=$(suitecrm_db_query "SELECT id, part_number, price, cost, aos_products_category_id, UNIX_TIMESTAMP(date_entered) FROM aos_products WHERE name='TempSense Pro X200' AND deleted=0 LIMIT 1")
P1_ID=$(echo "$P1_DATA" | awk -F'\t' '{print $1}')
P1_PART=$(echo "$P1_DATA" | awk -F'\t' '{print $2}')
P1_PRICE=$(echo "$P1_DATA" | awk -F'\t' '{print $3}')
P1_COST=$(echo "$P1_DATA" | awk -F'\t' '{print $4}')
P1_CAT_ID=$(echo "$P1_DATA" | awk -F'\t' '{print $5}')
P1_TS=$(echo "$P1_DATA" | awk -F'\t' '{print $6}')

# Product 2 info
P2_DATA=$(suitecrm_db_query "SELECT id, part_number, price, cost, aos_products_category_id, UNIX_TIMESTAMP(date_entered) FROM aos_products WHERE name='PressureGuard M500' AND deleted=0 LIMIT 1")
P2_ID=$(echo "$P2_DATA" | awk -F'\t' '{print $1}')
P2_PART=$(echo "$P2_DATA" | awk -F'\t' '{print $2}')
P2_PRICE=$(echo "$P2_DATA" | awk -F'\t' '{print $3}')
P2_COST=$(echo "$P2_DATA" | awk -F'\t' '{print $4}')
P2_CAT_ID=$(echo "$P2_DATA" | awk -F'\t' '{print $5}')
P2_TS=$(echo "$P2_DATA" | awk -F'\t' '{print $6}')

# Final counts
FINAL_PRODUCT_COUNT=$(suitecrm_count "aos_products" "deleted=0")
FINAL_CATEGORY_COUNT=$(suitecrm_count "aos_products_categories" "deleted=0")
INITIAL_PRODUCT_COUNT=$(cat /tmp/initial_product_count.txt 2>/dev/null || echo "0")
INITIAL_CATEGORY_COUNT=$(cat /tmp/initial_category_count.txt 2>/dev/null || echo "0")

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "category": {
    "exists": $(if [ -n "$CAT_ID" ]; then echo "true"; else echo "false"; fi),
    "id": "$(json_escape "${CAT_ID:-}")",
    "description": "$(json_escape "${CAT_DESC:-}")",
    "timestamp": "${CAT_TS:-0}"
  },
  "product1": {
    "exists": $(if [ -n "$P1_ID" ]; then echo "true"; else echo "false"; fi),
    "id": "$(json_escape "${P1_ID:-}")",
    "part_number": "$(json_escape "${P1_PART:-}")",
    "price": "$(json_escape "${P1_PRICE:-}")",
    "cost": "$(json_escape "${P1_COST:-}")",
    "category_id": "$(json_escape "${P1_CAT_ID:-}")",
    "timestamp": "${P1_TS:-0}"
  },
  "product2": {
    "exists": $(if [ -n "$P2_ID" ]; then echo "true"; else echo "false"; fi),
    "id": "$(json_escape "${P2_ID:-}")",
    "part_number": "$(json_escape "${P2_PART:-}")",
    "price": "$(json_escape "${P2_PRICE:-}")",
    "cost": "$(json_escape "${P2_COST:-}")",
    "category_id": "$(json_escape "${P2_CAT_ID:-}")",
    "timestamp": "${P2_TS:-0}"
  },
  "counts": {
    "initial_products": $INITIAL_PRODUCT_COUNT,
    "initial_categories": $INITIAL_CATEGORY_COUNT,
    "final_products": $FINAL_PRODUCT_COUNT,
    "final_categories": $FINAL_CATEGORY_COUNT
  }
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Export complete:"
cat /tmp/task_result.json