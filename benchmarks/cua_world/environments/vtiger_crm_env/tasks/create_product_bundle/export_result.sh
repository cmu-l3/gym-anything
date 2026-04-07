#!/bin/bash
echo "=== Exporting create_product_bundle results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_bundle_final.png

INITIAL_PRODUCT_COUNT=$(cat /tmp/initial_product_count.txt 2>/dev/null || echo "0")
CURRENT_PRODUCT_COUNT=$(vtiger_count "vtiger_products p INNER JOIN vtiger_crmentity c ON c.crmid=p.productid" "c.deleted=0")

PRODUCT_DATA=$(vtiger_db_query "SELECT p.productid, p.productname, p.product_no, p.unit_price, p.qtyinstock, p.usageunit FROM vtiger_products p INNER JOIN vtiger_crmentity c ON c.crmid=p.productid WHERE p.productname='Smart Home Starter Kit' AND c.deleted=0 ORDER BY p.productid DESC LIMIT 1")

PRODUCT_FOUND="false"
if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    P_ID=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $1}')
    P_NAME=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $2}')
    P_PART=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $3}')
    P_PRICE=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $4}')
    P_STOCK=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $5}')
    P_UNIT=$(echo "$PRODUCT_DATA" | awk -F'\t' '{print $6}')

    # Query related products via standard seproductsrel table (Parent to Sub-products)
    LINKED_SEPRODUCTS=$(vtiger_db_query "SELECT p2.productname FROM vtiger_seproductsrel r JOIN vtiger_products p2 ON r.spcrmid = p2.productid INNER JOIN vtiger_crmentity c2 ON c2.crmid=p2.productid WHERE r.crmid=${P_ID} AND c2.deleted=0" | tr '\n' ',' | sed 's/,$//')
    
    # Query fallback crmentityrel (Arbitrary relations)
    LINKED_CRMENTITYREL=$(vtiger_db_query "SELECT p2.productname FROM vtiger_crmentityrel r JOIN vtiger_products p2 ON r.relcrmid = p2.productid INNER JOIN vtiger_crmentity c2 ON c2.crmid=p2.productid WHERE r.crmid=${P_ID} AND r.module='Products' AND r.relmodule='Products' AND c2.deleted=0" | tr '\n' ',' | sed 's/,$//')
    
    # Query reverse seproductsrel (in case UI binds them inversely)
    LINKED_SEPRODUCTS_REV=$(vtiger_db_query "SELECT p2.productname FROM vtiger_seproductsrel r JOIN vtiger_products p2 ON r.crmid = p2.productid INNER JOIN vtiger_crmentity c2 ON c2.crmid=p2.productid WHERE r.spcrmid=${P_ID} AND c2.deleted=0" | tr '\n' ',' | sed 's/,$//')
fi

RESULT_JSON=$(cat << JSONEOF
{
  "product_found": ${PRODUCT_FOUND},
  "product_id": "$(json_escape "${P_ID:-}")",
  "product_name": "$(json_escape "${P_NAME:-}")",
  "part_number": "$(json_escape "${P_PART:-}")",
  "unit_price": "$(json_escape "${P_PRICE:-}")",
  "qty_in_stock": "$(json_escape "${P_STOCK:-}")",
  "usage_unit": "$(json_escape "${P_UNIT:-}")",
  "linked_seproducts": "$(json_escape "${LINKED_SEPRODUCTS:-}")",
  "linked_crmentityrel": "$(json_escape "${LINKED_CRMENTITYREL:-}")",
  "linked_seproducts_rev": "$(json_escape "${LINKED_SEPRODUCTS_REV:-}")",
  "initial_count": ${INITIAL_PRODUCT_COUNT},
  "current_count": ${CURRENT_PRODUCT_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/create_bundle_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_bundle_result.json"
echo "$RESULT_JSON"
echo "=== create_product_bundle export complete ==="