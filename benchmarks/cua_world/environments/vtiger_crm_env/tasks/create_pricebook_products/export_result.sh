#!/bin/bash
echo "=== Exporting create_pricebook_products results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

INITIAL_PB_COUNT=$(cat /tmp/initial_pb_count.txt 2>/dev/null || echo "0")
CURRENT_PB_COUNT=$(vtiger_count "vtiger_pricebook")

# Find Price Book
PB_DATA=$(vtiger_db_query "SELECT p.pricebookid, p.bookname, p.active, p.currency_id, e.description, e.createdtime FROM vtiger_pricebook p INNER JOIN vtiger_crmentity e ON p.pricebookid = e.crmid WHERE p.bookname='Premium Partner Pricing Q1 2025' AND e.deleted=0 LIMIT 1")

PB_FOUND="false"
PB_ID=""
PB_NAME=""
PB_ACTIVE="0"
PB_CURRENCY=""
PB_DESC=""
PB_CREATED=""

if [ -n "$PB_DATA" ]; then
    PB_FOUND="true"
    PB_ID=$(echo "$PB_DATA" | awk -F'\t' '{print $1}')
    PB_NAME=$(echo "$PB_DATA" | awk -F'\t' '{print $2}')
    PB_ACTIVE=$(echo "$PB_DATA" | awk -F'\t' '{print $3}')
    PB_CURRENCY=$(echo "$PB_DATA" | awk -F'\t' '{print $4}')
    PB_DESC=$(echo "$PB_DATA" | awk -F'\t' '{print $5}')
    PB_CREATED=$(echo "$PB_DATA" | awk -F'\t' '{print $6}')
fi

# Fetch products associated with this pricebook
PROD1_ASSOC="false"
PROD1_PRICE="0"
PROD2_ASSOC="false"
PROD2_PRICE="0"
PROD3_ASSOC="false"
PROD3_PRICE="0"

if [ "$PB_FOUND" = "true" ]; then
    PROD1_DATA=$(vtiger_db_query "SELECT pr.listprice FROM vtiger_pricebookproductrel pr INNER JOIN vtiger_products p ON pr.productid = p.productid WHERE pr.pricebookid=$PB_ID AND p.productname='Wireless Bluetooth Headset' LIMIT 1")
    if [ -n "$PROD1_DATA" ]; then
        PROD1_ASSOC="true"
        PROD1_PRICE=$(echo "$PROD1_DATA" | tr -d '[:space:]')
    fi

    PROD2_DATA=$(vtiger_db_query "SELECT pr.listprice FROM vtiger_pricebookproductrel pr INNER JOIN vtiger_products p ON pr.productid = p.productid WHERE pr.pricebookid=$PB_ID AND p.productname='USB-C Docking Station' LIMIT 1")
    if [ -n "$PROD2_DATA" ]; then
        PROD2_ASSOC="true"
        PROD2_PRICE=$(echo "$PROD2_DATA" | tr -d '[:space:]')
    fi

    PROD3_DATA=$(vtiger_db_query "SELECT pr.listprice FROM vtiger_pricebookproductrel pr INNER JOIN vtiger_products p ON pr.productid = p.productid WHERE pr.pricebookid=$PB_ID AND p.productname='Ergonomic Keyboard Pro' LIMIT 1")
    if [ -n "$PROD3_DATA" ]; then
        PROD3_ASSOC="true"
        PROD3_PRICE=$(echo "$PROD3_DATA" | tr -d '[:space:]')
    fi
fi

# Determine if created during task
PB_CREATED_TS="0"
if [ -n "$PB_CREATED" ]; then
    PB_CREATED_TS=$(date -d "$PB_CREATED" +%s 2>/dev/null || echo "0")
fi

CREATED_DURING_TASK="false"
if [ "$PB_CREATED_TS" -gt "$TASK_START" ] || [ "$CURRENT_PB_COUNT" -gt "$INITIAL_PB_COUNT" ]; then
    CREATED_DURING_TASK="true"
fi

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "pb_found": $PB_FOUND,
  "pb_id": "$(json_escape "${PB_ID:-}")",
  "bookname": "$(json_escape "${PB_NAME:-}")",
  "active": "$PB_ACTIVE",
  "currency_id": "$PB_CURRENCY",
  "description": "$(json_escape "${PB_DESC:-}")",
  "createdtime": "$(json_escape "${PB_CREATED:-}")",
  "created_during_task": $CREATED_DURING_TASK,
  "prod1_assoc": $PROD1_ASSOC,
  "prod1_price": "$PROD1_PRICE",
  "prod2_assoc": $PROD2_ASSOC,
  "prod2_price": "$PROD2_PRICE",
  "prod3_assoc": $PROD3_ASSOC,
  "prod3_price": "$PROD3_PRICE",
  "initial_count": $INITIAL_PB_COUNT,
  "current_count": $CURRENT_PB_COUNT
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== export complete ==="