#!/bin/bash
echo "=== Exporting receive_purchase_order results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_STOCK=$(cat /tmp/initial_product_stock.txt 2>/dev/null || echo "0")

take_screenshot /tmp/receive_po_final.png

# Query the Purchase Order current state
PO_DATA=$(vtiger_db_query "SELECT p.purchaseorderid, p.subject, p.postatus, p.tracking_no, p.carrier, UNIX_TIMESTAMP(e.modifiedtime) FROM vtiger_purchaseorder p JOIN vtiger_crmentity e ON p.purchaseorderid = e.crmid WHERE p.subject='Restock Milwaukee Tools Q1' LIMIT 1")

PO_FOUND="false"
if [ -n "$PO_DATA" ]; then
    PO_FOUND="true"
    PO_ID=$(echo "$PO_DATA" | awk -F'\t' '{print $1}')
    PO_SUBJECT=$(echo "$PO_DATA" | awk -F'\t' '{print $2}')
    PO_STATUS=$(echo "$PO_DATA" | awk -F'\t' '{print $3}')
    PO_TRACKING=$(echo "$PO_DATA" | awk -F'\t' '{print $4}')
    PO_CARRIER=$(echo "$PO_DATA" | awk -F'\t' '{print $5}')
    PO_MTIME=$(echo "$PO_DATA" | awk -F'\t' '{print $6}')
fi

# Query the Product current stock
CURRENT_STOCK=$(vtiger_db_query "SELECT qtyinstock FROM vtiger_products WHERE productname='Milwaukee M18 Impact Driver' LIMIT 1" | tr -d '[:space:]')

RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START},
  "task_end_time": ${TASK_END},
  "po_found": ${PO_FOUND},
  "po_id": "$(json_escape "${PO_ID:-}")",
  "subject": "$(json_escape "${PO_SUBJECT:-}")",
  "status": "$(json_escape "${PO_STATUS:-}")",
  "tracking_no": "$(json_escape "${PO_TRACKING:-}")",
  "carrier": "$(json_escape "${PO_CARRIER:-}")",
  "modified_time": ${PO_MTIME:-0},
  "initial_stock": ${INITIAL_STOCK:-0},
  "current_stock": ${CURRENT_STOCK:-0}
}
JSONEOF
)

safe_write_result "/tmp/receive_po_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/receive_po_result.json"
echo "$RESULT_JSON"
echo "=== receive_purchase_order export complete ==="