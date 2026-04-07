#!/bin/bash
echo "=== Exporting convert_sales_order_to_invoice results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather context timestamps & IDs
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PREREQ_SO_ID=$(cat /tmp/prereq_so_id.txt 2>/dev/null || echo "0")
PREREQ_ORG_ID=$(cat /tmp/prereq_org_id.txt 2>/dev/null || echo "0")

# 3. Query the generated Invoice from DB
# Using a TSV format export via vtiger_db_query
INVOICE_DATA=$(vtiger_db_query "SELECT i.invoiceid, i.accountid, i.salesorderid, i.s_h_amount, i.total, i.invoicestatus, UNIX_TIMESTAMP(c.createdtime) FROM vtiger_invoice i JOIN vtiger_crmentity c ON i.invoiceid = c.crmid WHERE i.subject='INV-2026-Alpha' AND c.deleted=0 ORDER BY i.invoiceid DESC LIMIT 1")

INVOICE_FOUND="false"
I_ID=""
I_ORG_ID=""
I_SO_ID=""
I_SH_AMOUNT="0.00"
I_TOTAL="0.00"
I_STATUS=""
I_CREATED_TIME="0"
LINE_ITEM_COUNT="0"

if [ -n "$INVOICE_DATA" ]; then
    INVOICE_FOUND="true"
    I_ID=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $1}')
    I_ORG_ID=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $2}')
    I_SO_ID=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $3}')
    I_SH_AMOUNT=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $4}')
    I_TOTAL=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $5}')
    I_STATUS=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $6}')
    I_CREATED_TIME=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $7}')
    
    # Check if line items were successfully carried over
    LINE_ITEM_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_inventoryproductrel WHERE id=${I_ID}" | tr -d '[:space:]')
fi

# 4. Save to JSON for the verifier
RESULT_JSON=$(cat << JSONEOF
{
  "invoice_found": ${INVOICE_FOUND},
  "invoice_id": "$(json_escape "${I_ID}")",
  "org_id": "$(json_escape "${I_ORG_ID}")",
  "sales_order_id": "$(json_escape "${I_SO_ID}")",
  "shipping_amount": "$(json_escape "${I_SH_AMOUNT}")",
  "total": "$(json_escape "${I_TOTAL}")",
  "status": "$(json_escape "${I_STATUS}")",
  "created_time": ${I_CREATED_TIME:-0},
  "line_item_count": ${LINE_ITEM_COUNT:-0},
  "task_start_time": ${TASK_START},
  "expected_so_id": "$(json_escape "${PREREQ_SO_ID}")",
  "expected_org_id": "$(json_escape "${PREREQ_ORG_ID}")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== convert_sales_order_to_invoice export complete ==="