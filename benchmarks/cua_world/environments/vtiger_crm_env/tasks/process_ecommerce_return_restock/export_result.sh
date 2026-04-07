#!/bin/bash
echo "=== Exporting process_ecommerce_return_restock results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read variables recorded during setup
IID=$(cat /tmp/target_iid.txt 2>/dev/null || echo "0")
CID=$(cat /tmp/target_cid.txt 2>/dev/null || echo "0")
PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")
INITIAL_QTY=$(cat /tmp/initial_qty.txt 2>/dev/null || echo "0.000")
START_TIME_SQL=$(cat /tmp/task_start_mysql.txt 2>/dev/null || echo "2000-01-01 00:00:00")

# 1. Invoice Status Check
INVOICE_STATUS=$(vtiger_db_query "SELECT invoicestatus FROM vtiger_invoice WHERE invoiceid=$IID" | tr -d '[:space:]' | tr -d '\r')

# 2. Invoice Comments Check (must be added during the task)
# vtiger_crmentity.related_to tracks the link to the invoice
COMMENTS=$(vtiger_db_query "SELECT mc.commentcontent FROM vtiger_modcomments mc JOIN vtiger_crmentity ce ON mc.modcommentsid=ce.crmid WHERE ce.related_to=$IID AND ce.createdtime >= '$START_TIME_SQL'" | tr '\n' ' ' | tr -d '\r')

# 3. RMA Ticket Check
# Looking for tickets created after the task started with RMA or Return in the title
TICKET_DATA=$(vtiger_db_query "SELECT t.ticketid, t.title, t.status, t.contact_id, t.product_id FROM vtiger_troubletickets t JOIN vtiger_crmentity ce ON t.ticketid=ce.crmid WHERE (t.title LIKE '%RMA%' OR t.title LIKE '%Return%') AND ce.createdtime >= '$START_TIME_SQL' ORDER BY t.ticketid DESC LIMIT 1")

TICKET_FOUND="false"
T_ID=""
T_TITLE=""
T_STATUS=""
T_CONTACT_ID=""
T_PRODUCT_ID=""

if [ -n "$TICKET_DATA" ]; then
    TICKET_FOUND="true"
    T_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $1}')
    T_TITLE=$(echo "$TICKET_DATA" | awk -F'\t' '{print $2}')
    T_STATUS=$(echo "$TICKET_DATA" | awk -F'\t' '{print $3}')
    T_CONTACT_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $4}')
    T_PRODUCT_ID=$(echo "$TICKET_DATA" | awk -F'\t' '{print $5}')
fi

# 4. Product Quantity Check
CURRENT_QTY=$(vtiger_db_query "SELECT qtyinstock FROM vtiger_products WHERE productid=$PID" | tr -d '[:space:]' | tr -d '\r')

# Construct JSON output
RESULT_JSON=$(cat << JSONEOF
{
  "target_ids": {
    "invoice_id": "$IID",
    "contact_id": "$CID",
    "product_id": "$PID"
  },
  "invoice": {
    "status": "$(json_escape "${INVOICE_STATUS:-}")",
    "comments": "$(json_escape "${COMMENTS:-}")"
  },
  "ticket": {
    "found": ${TICKET_FOUND},
    "id": "$(json_escape "${T_ID:-}")",
    "title": "$(json_escape "${T_TITLE:-}")",
    "status": "$(json_escape "${T_STATUS:-}")",
    "contact_id": "$(json_escape "${T_CONTACT_ID:-}")",
    "product_id": "$(json_escape "${T_PRODUCT_ID:-}")"
  },
  "inventory": {
    "initial_qty": "$INITIAL_QTY",
    "current_qty": "$CURRENT_QTY"
  }
}
JSONEOF
)

# Write result safely
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="