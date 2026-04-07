#!/bin/bash
echo "=== Exporting setup_recurring_sales_order results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/setup_recurring_sales_order_final.png

# 2. Retrieve start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query the Sales Order and related records
SO_DATA=$(vtiger_db_query "SELECT s.salesorderid, s.subject, s.sostatus, s.enable_recurring, e.createdtime, a.accountname FROM vtiger_salesorder s JOIN vtiger_crmentity e ON s.salesorderid=e.crmid LEFT JOIN vtiger_account a ON s.accountid=a.accountid WHERE s.subject='2025 Printer Lease Contract - Global Trade Corp' AND e.deleted=0 ORDER BY s.salesorderid DESC LIMIT 1")

SO_FOUND="false"
if [ -n "$SO_DATA" ]; then
    SO_FOUND="true"
    SO_ID=$(echo "$SO_DATA" | awk -F'\t' '{print $1}')
    SO_SUBJECT=$(echo "$SO_DATA" | awk -F'\t' '{print $2}')
    SO_STATUS=$(echo "$SO_DATA" | awk -F'\t' '{print $3}')
    SO_RECURRING=$(echo "$SO_DATA" | awk -F'\t' '{print $4}')
    SO_CREATED=$(echo "$SO_DATA" | awk -F'\t' '{print $5}')
    SO_ACCOUNT=$(echo "$SO_DATA" | awk -F'\t' '{print $6}')

    # Query Recurring Information Block
    REC_DATA=$(vtiger_db_query "SELECT recurring_frequency, start_period, end_period, payment_duration, invoice_status FROM vtiger_invoice_recurring_info WHERE salesorderid=$SO_ID LIMIT 1")
    REC_FREQ=$(echo "$REC_DATA" | awk -F'\t' '{print $1}')
    REC_START=$(echo "$REC_DATA" | awk -F'\t' '{print $2}')
    REC_END=$(echo "$REC_DATA" | awk -F'\t' '{print $3}')
    REC_PAYMENT=$(echo "$REC_DATA" | awk -F'\t' '{print $4}')
    REC_STATUS=$(echo "$REC_DATA" | awk -F'\t' '{print $5}')

    # Query Inventory Line Items
    ITEM_DATA=$(vtiger_db_query "SELECT rel.quantity, rel.listprice, s.servicename FROM vtiger_inventoryproductrel rel JOIN vtiger_service s ON rel.productid=s.serviceid WHERE rel.id=$SO_ID LIMIT 1")
    ITEM_QTY=$(echo "$ITEM_DATA" | awk -F'\t' '{print $1}')
    ITEM_PRICE=$(echo "$ITEM_DATA" | awk -F'\t' '{print $2}')
    ITEM_NAME=$(echo "$ITEM_DATA" | awk -F'\t' '{print $3}')
fi

# 4. Construct JSON result
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START},
  "sales_order_found": ${SO_FOUND},
  "sales_order_id": "$(json_escape "${SO_ID:-}")",
  "subject": "$(json_escape "${SO_SUBJECT:-}")",
  "status": "$(json_escape "${SO_STATUS:-}")",
  "enable_recurring": "$(json_escape "${SO_RECURRING:-}")",
  "created_time": "$(json_escape "${SO_CREATED:-}")",
  "account_name": "$(json_escape "${SO_ACCOUNT:-}")",
  "recurring_frequency": "$(json_escape "${REC_FREQ:-}")",
  "start_period": "$(json_escape "${REC_START:-}")",
  "end_period": "$(json_escape "${REC_END:-}")",
  "payment_duration": "$(json_escape "${REC_PAYMENT:-}")",
  "invoice_status": "$(json_escape "${REC_STATUS:-}")",
  "item_quantity": "$(json_escape "${ITEM_QTY:-}")",
  "item_price": "$(json_escape "${ITEM_PRICE:-}")",
  "item_service_name": "$(json_escape "${ITEM_NAME:-}")"
}
JSONEOF
)

# 5. Save securely
safe_write_result "/tmp/setup_recurring_sales_order_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/setup_recurring_sales_order_result.json"
echo "$RESULT_JSON"
echo "=== setup_recurring_sales_order export complete ==="