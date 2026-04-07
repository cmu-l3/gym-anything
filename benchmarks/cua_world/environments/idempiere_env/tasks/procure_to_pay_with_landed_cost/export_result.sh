#!/bin/bash
set -e
echo "=== Exporting procure_to_pay_with_landed_cost results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# --- A. Check Purchase Order ---
PO_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT
        o.c_order_id,
        o.documentno,
        o.docstatus,
        o.grandtotal,
        (SELECT count(*) FROM c_orderline ol
         JOIN m_product p ON ol.m_product_id = p.m_product_id
         WHERE ol.c_order_id = o.c_order_id
           AND p.name = 'Azalea Bush'
           AND ol.qtyordered = 200) as correct_lines
    FROM c_order o
    JOIN c_bpartner bp ON o.c_bpartner_id = bp.c_bpartner_id
    WHERE o.issotrx = 'N'
      AND o.ad_client_id = $CLIENT_ID
      AND bp.name = 'Seed Farm Inc.'
      AND o.created >= to_timestamp($TASK_START)
    ORDER BY o.created DESC
    LIMIT 1
) t
" 2>/dev/null || echo "{}")

# --- B. Check Material Receipt ---
RECEIPT_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT
        io.m_inout_id,
        io.documentno,
        io.docstatus,
        (SELECT count(*) FROM m_inoutline iol
         JOIN m_product p ON iol.m_product_id = p.m_product_id
         WHERE iol.m_inout_id = io.m_inout_id
           AND p.name = 'Azalea Bush'
           AND iol.movementqty = 200) as correct_lines
    FROM m_inout io
    JOIN c_bpartner bp ON io.c_bpartner_id = bp.c_bpartner_id
    WHERE io.issotrx = 'N'
      AND io.ad_client_id = $CLIENT_ID
      AND bp.name = 'Seed Farm Inc.'
      AND io.created >= to_timestamp($TASK_START)
    ORDER BY io.created DESC
    LIMIT 1
) t
" 2>/dev/null || echo "{}")

# --- C. Check Goods Invoice ($500) ---
GOODS_INV_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT
        i.c_invoice_id,
        i.documentno,
        i.docstatus,
        i.grandtotal,
        i.ispaid
    FROM c_invoice i
    JOIN c_bpartner bp ON i.c_bpartner_id = bp.c_bpartner_id
    WHERE i.issotrx = 'N'
      AND i.ad_client_id = $CLIENT_ID
      AND bp.name = 'Seed Farm Inc.'
      AND i.grandtotal BETWEEN 2500 AND 6000
      AND i.created >= to_timestamp($TASK_START)
    ORDER BY i.created ASC
    LIMIT 1
) t
" 2>/dev/null || echo "{}")

# --- D. Check Freight Invoice ($75) ---
FREIGHT_INV_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT
        i.c_invoice_id,
        i.documentno,
        i.docstatus,
        i.grandtotal,
        i.ispaid
    FROM c_invoice i
    JOIN c_bpartner bp ON i.c_bpartner_id = bp.c_bpartner_id
    WHERE i.issotrx = 'N'
      AND i.ad_client_id = $CLIENT_ID
      AND bp.name = 'Seed Farm Inc.'
      AND i.grandtotal BETWEEN 70 AND 80
      AND i.created >= to_timestamp($TASK_START)
    ORDER BY i.created DESC
    LIMIT 1
) t
" 2>/dev/null || echo "{}")

# --- E. Check Landed Cost Allocation ---
LCA_FOUND="false"
LCA_COUNT=$(idempiere_query "
SELECT COUNT(*)
FROM c_landedcostallocation lca
WHERE lca.ad_client_id = $CLIENT_ID
  AND lca.created >= to_timestamp($TASK_START)
" 2>/dev/null || echo "0")
if [ "$LCA_COUNT" -gt "0" ] 2>/dev/null; then
    LCA_FOUND="true"
fi

# --- F. Check Vendor Payment ($575) ---
PAYMENT_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT
        p.c_payment_id,
        p.documentno,
        p.docstatus,
        p.payamt,
        p.checkno,
        p.isallocated
    FROM c_payment p
    JOIN c_bpartner bp ON p.c_bpartner_id = bp.c_bpartner_id
    WHERE p.isreceipt = 'N'
      AND p.ad_client_id = $CLIENT_ID
      AND bp.name = 'Seed Farm Inc.'
      AND p.payamt BETWEEN 2500 AND 6100
      AND p.created >= to_timestamp($TASK_START)
    ORDER BY p.created DESC
    LIMIT 1
) t
" 2>/dev/null || echo "{}")

# --- G. Check Payment Allocation (covers both invoices) ---
ALLOC_FOUND="false"
ALLOC_COUNT="0"
PAYMENT_ID=""
if [ -n "$PAYMENT_JSON" ] && [ "$PAYMENT_JSON" != "{}" ]; then
    PAYMENT_ID=$(echo "$PAYMENT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('c_payment_id',''))" 2>/dev/null || echo "")
fi

if [ -n "$PAYMENT_ID" ]; then
    ALLOC_COUNT=$(idempiere_query "
    SELECT COUNT(DISTINCT al.c_invoice_id)
    FROM c_allocationline al
    JOIN c_allocationhdr ah ON al.c_allocationhdr_id = ah.c_allocationhdr_id
    WHERE al.c_payment_id = $PAYMENT_ID
      AND ah.ad_client_id = $CLIENT_ID
      AND ah.docstatus IN ('CO','CL')
    " 2>/dev/null || echo "0")
    if [ "$ALLOC_COUNT" -ge "2" ] 2>/dev/null; then
        ALLOC_FOUND="true"
    fi
fi

# 2. Construct JSON Result - use null for empty query results
PO_JSON=${PO_JSON:-null}
RECEIPT_JSON=${RECEIPT_JSON:-null}
GOODS_INV_JSON=${GOODS_INV_JSON:-null}
FREIGHT_INV_JSON=${FREIGHT_INV_JSON:-null}
PAYMENT_JSON=${PAYMENT_JSON:-null}
LCA_COUNT=${LCA_COUNT:-0}
ALLOC_COUNT=${ALLOC_COUNT:-0}

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "purchase_order": $PO_JSON,
    "material_receipt": $RECEIPT_JSON,
    "goods_invoice": $GOODS_INV_JSON,
    "freight_invoice": $FREIGHT_INV_JSON,
    "landed_cost_allocation_found": $LCA_FOUND,
    "landed_cost_allocation_count": $LCA_COUNT,
    "payment": $PAYMENT_JSON,
    "payment_allocation_found": $ALLOC_FOUND,
    "payment_allocation_invoice_count": $ALLOC_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 3. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
