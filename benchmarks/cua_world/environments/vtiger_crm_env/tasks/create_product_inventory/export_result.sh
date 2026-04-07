#!/bin/bash
echo "=== Exporting create_product_inventory results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Read counts
INITIAL_PRODUCT_COUNT=$(cat /tmp/initial_product_count.txt 2>/dev/null || echo "0")
CURRENT_PRODUCT_COUNT=$(vtiger_count "vtiger_products" "1=1")

# Query the product data
# Note: we use awk with tab delimiter, so we exclude description from this query to avoid tab/newline breakage
PRODUCT_DATA=$(vtiger_db_query "SELECT productid, productname, unit_price, qty_per_unit, qtyinstock, reorderlevel, qtyindemand, discontinued FROM vtiger_products WHERE productname='Bamboo Standing Desk Pro' ORDER BY productid DESC LIMIT 1")

PRODUCT_FOUND="false"
P_ID=""
P_DESC=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    P_ID=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $1}')
    P_NAME=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $2}')
    P_PRICE=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $3}')
    P_PACK=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $4}')
    P_STOCK=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $5}')
    P_REORDER=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $6}')
    P_DEMAND=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $7}')
    P_DISC=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $8}')
    
    # Query description separately to avoid parsing issues
    P_DESC=$(vtiger_db_query "SELECT description FROM vtiger_crmentity WHERE crmid=$P_ID" 2>/dev/null || echo "")
fi

# Create JSON structure manually using task_utils escaping
RESULT_JSON=$(cat << JSONEOF
{
  "product_found": ${PRODUCT_FOUND},
  "product_id": "$(json_escape "${P_ID:-}")",
  "name": "$(json_escape "${P_NAME:-}")",
  "unit_price": "$(json_escape "${P_PRICE:-}")",
  "qty_per_unit": "$(json_escape "${P_PACK:-}")",
  "qtyinstock": "$(json_escape "${P_STOCK:-}")",
  "reorderlevel": "$(json_escape "${P_REORDER:-}")",
  "qtyindemand": "$(json_escape "${P_DEMAND:-}")",
  "discontinued": "$(json_escape "${P_DISC:-}")",
  "description": "$(json_escape "${P_DESC:-}")",
  "initial_count": ${INITIAL_PRODUCT_COUNT},
  "current_count": ${CURRENT_PRODUCT_COUNT}
}
JSONEOF
)

# Save result to file safely
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="