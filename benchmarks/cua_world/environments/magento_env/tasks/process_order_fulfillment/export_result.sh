#!/bin/bash
# Export script for Process Order Fulfillment task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get DB Data
ORDER_ID=$(magento_query "SELECT entity_id FROM sales_order WHERE increment_id='000000001'" 2>/dev/null | tail -1)

if [ -z "$ORDER_ID" ]; then
    echo "Error: Order #000000001 not found."
    ORDER_FOUND="false"
else
    ORDER_FOUND="true"
    
    # Get Order Status
    ORDER_STATUS=$(magento_query "SELECT status FROM sales_order WHERE entity_id=$ORDER_ID" 2>/dev/null | tail -1)
    
    # Get Invoice info
    INVOICE_DATA=$(magento_query "SELECT entity_id, state, grand_total, created_at FROM sales_invoice WHERE order_id=$ORDER_ID ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1)
    INVOICE_EXISTS="false"
    if [ -n "$INVOICE_DATA" ]; then
        INVOICE_EXISTS="true"
        INVOICE_STATE=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $2}')
        INVOICE_TOTAL=$(echo "$INVOICE_DATA" | awk -F'\t' '{print $3}')
    fi
    
    # Get Shipment info
    SHIPMENT_DATA=$(magento_query "SELECT entity_id, created_at FROM sales_shipment WHERE order_id=$ORDER_ID ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1)
    SHIPMENT_EXISTS="false"
    if [ -n "$SHIPMENT_DATA" ]; then
        SHIPMENT_EXISTS="true"
        SHIPMENT_ID=$(echo "$SHIPMENT_DATA" | awk -F'\t' '{print $1}')
        
        # Get Tracking info for this shipment
        TRACK_DATA=$(magento_query "SELECT track_number, title, carrier_code FROM sales_shipment_track WHERE parent_id=$SHIPMENT_ID LIMIT 1" 2>/dev/null | tail -1)
        TRACK_NUMBER=$(echo "$TRACK_DATA" | awk -F'\t' '{print $1}')
        TRACK_TITLE=$(echo "$TRACK_DATA" | awk -F'\t' '{print $2}')
    fi
fi

# 3. Get Counts for Anti-Gaming
INITIAL_INVOICE_COUNT=$(cat /tmp/initial_invoice_count.txt 2>/dev/null || echo "0")
CURRENT_INVOICE_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_invoice" 2>/dev/null | tail -1)
INITIAL_SHIPMENT_COUNT=$(cat /tmp/initial_shipment_count.txt 2>/dev/null || echo "0")
CURRENT_SHIPMENT_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_shipment" 2>/dev/null | tail -1)

# 4. Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "order_found": $ORDER_FOUND,
    "order_id": "${ORDER_ID:-}",
    "order_status": "${ORDER_STATUS:-}",
    "invoice": {
        "exists": ${INVOICE_EXISTS:-false},
        "state": "${INVOICE_STATE:-}",
        "total": "${INVOICE_TOTAL:-0}"
    },
    "shipment": {
        "exists": ${SHIPMENT_EXISTS:-false},
        "id": "${SHIPMENT_ID:-}",
        "tracking_number": "${TRACK_NUMBER:-}",
        "tracking_title": "${TRACK_TITLE:-}"
    },
    "counts": {
        "initial_invoices": ${INITIAL_INVOICE_COUNT:-0},
        "current_invoices": ${CURRENT_INVOICE_COUNT:-0},
        "initial_shipments": ${INITIAL_SHIPMENT_COUNT:-0},
        "current_shipments": ${CURRENT_SHIPMENT_COUNT:-0}
    },
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/process_order_result.json
echo "Result exported to /tmp/process_order_result.json"
cat /tmp/process_order_result.json