#!/bin/bash
set -e
echo "=== Exporting process_sales_payment_cycle results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Find the Invoice created during the task
# Criteria: For Joe Block, Contains Oak Tree, Created after task start
# We get the most recent one fitting criteria
INVOICE_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT 
        i.c_invoice_id,
        i.documentno,
        i.grandtotal,
        i.ispaid,
        i.docstatus,
        (SELECT count(*) FROM c_invoiceline il 
         JOIN m_product p ON il.m_product_id = p.m_product_id 
         WHERE il.c_invoice_id = i.c_invoice_id AND p.name = 'Oak Tree' AND il.qtyinvoiced = 5) as correct_lines
    FROM c_invoice i
    JOIN c_bpartner bp ON i.c_bpartner_id = bp.c_bpartner_id
    WHERE bp.name = 'Joe Block'
      AND i.ad_client_id = $CLIENT_ID
      AND i.issotrx = 'Y'
      AND i.created >= to_timestamp($TASK_START_TIME)
    ORDER BY i.created DESC
    LIMIT 1
) t
" 2>/dev/null || echo "{}")

# 3. Find the Payment created during the task
PAYMENT_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT 
        p.c_payment_id,
        p.documentno,
        p.payamt,
        p.checkno,
        p.docstatus,
        p.isallocated
    FROM c_payment p
    JOIN c_bpartner bp ON p.c_bpartner_id = bp.c_bpartner_id
    WHERE bp.name = 'Joe Block'
      AND p.ad_client_id = $CLIENT_ID
      AND p.isreceipt = 'Y'
      AND p.created >= to_timestamp($TASK_START_TIME)
    ORDER BY p.created DESC
    LIMIT 1
) t
" 2>/dev/null || echo "{}")

# 4. Check for Allocation linking this specific Invoice and Payment
ALLOCATION_FOUND="false"
ALLOCATION_DOC_STATUS=""

if [ -n "$INVOICE_JSON" ] && [ "$INVOICE_JSON" != "{}" ] && [ -n "$PAYMENT_JSON" ] && [ "$PAYMENT_JSON" != "{}" ]; then
    # Extract IDs safely using python because jq might not be available or shell parsing JSON is fragile
    INV_ID=$(echo "$INVOICE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('c_invoice_id'))")
    PAY_ID=$(echo "$PAYMENT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('c_payment_id'))")
    
    if [ -n "$INV_ID" ] && [ -n "$PAY_ID" ]; then
        ALLOC_CHECK=$(idempiere_query "
        SELECT ah.docstatus
        FROM c_allocationline al
        JOIN c_allocationhdr ah ON al.c_allocationhdr_id = ah.c_allocationhdr_id
        WHERE al.c_invoice_id = $INV_ID
          AND al.c_payment_id = $PAY_ID
          AND ah.ad_client_id = $CLIENT_ID
          AND ah.docstatus IN ('CO', 'CL')
        LIMIT 1
        " 2>/dev/null)
        
        if [ -n "$ALLOC_CHECK" ]; then
            ALLOCATION_FOUND="true"
            ALLOCATION_DOC_STATUS="$ALLOC_CHECK"
        fi
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "invoice_data": $INVOICE_JSON,
    "payment_data": $PAYMENT_JSON,
    "allocation_found": $ALLOCATION_FOUND,
    "allocation_status": "$ALLOCATION_DOC_STATUS",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json