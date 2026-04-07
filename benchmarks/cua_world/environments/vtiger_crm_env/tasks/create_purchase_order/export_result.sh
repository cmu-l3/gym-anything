#!/bin/bash
echo "=== Exporting create_purchase_order result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_PO_COUNT=$(cat /tmp/initial_po_count.txt 2>/dev/null || echo "0")
CURRENT_PO_COUNT=$(vtiger_count "vtiger_purchaseorder" "1=1")

echo "PO Count: Initial=$INITIAL_PO_COUNT, Current=$CURRENT_PO_COUNT"

# Find the target Purchase Order by subject
PO_ID=$(vtiger_db_query "SELECT po.purchaseorderid FROM vtiger_purchaseorder po JOIN vtiger_crmentity ce ON po.purchaseorderid=ce.crmid WHERE po.subject='Spring 2025 Landscaping Materials' AND ce.deleted=0 ORDER BY po.purchaseorderid DESC LIMIT 1" | tr -d '[:space:]')

PO_FOUND="false"
VENDOR_NAME=""
PO_NUM=""
ITEMS_JSON="[]"

if [ -n "$PO_ID" ] && [ "$PO_ID" != "NULL" ]; then
    PO_FOUND="true"
    
    # Get associated vendor and PO details
    VENDOR_NAME=$(vtiger_db_query "SELECT v.vendorname FROM vtiger_purchaseorder po LEFT JOIN vtiger_vendor v ON po.vendorid=v.vendorid WHERE po.purchaseorderid=$PO_ID" | tr -d '\n' | sed 's/"/\\"/g')
    PO_NUM=$(vtiger_db_query "SELECT purchaseorder_no FROM vtiger_purchaseorder WHERE purchaseorderid=$PO_ID" | tr -d '[:space:]' | sed 's/"/\\"/g')
    
    # Get line items
    # Note: mysql -N outputs tab-separated values. We format this safely into a JSON array.
    ITEMS_TSV=$(vtiger_db_query "SELECT p.productname, ipr.quantity, ipr.listprice FROM vtiger_inventoryproductrel ipr JOIN vtiger_products p ON ipr.productid=p.productid WHERE ipr.id=$PO_ID")
    
    if [ -n "$ITEMS_TSV" ]; then
        ITEMS_JSON=$(echo "$ITEMS_TSV" | awk -F'\t' '
        BEGIN { printf "[" }
        {
            if (NR > 1) printf ", "
            # escape quotes
            gsub(/"/, "\\\"", $1)
            # handle empty numericals
            qty = ($2 == "") ? 0 : $2
            price = ($3 == "") ? 0 : $3
            printf "{\"productname\": \"%s\", \"quantity\": %f, \"listprice\": %f}", $1, qty, price
        }
        END { printf "]" }')
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/po_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_po_count": $INITIAL_PO_COUNT,
    "current_po_count": $CURRENT_PO_COUNT,
    "po_found": $PO_FOUND,
    "po_id": "$PO_ID",
    "vendor_name": "$VENDOR_NAME",
    "po_number": "$PO_NUM",
    "line_items": $ITEMS_JSON
}
EOF

safe_write_result "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="