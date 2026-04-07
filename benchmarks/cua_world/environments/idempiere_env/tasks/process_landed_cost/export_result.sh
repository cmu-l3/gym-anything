#!/bin/bash
set -e
echo "=== Exporting process_landed_cost results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 3. Query Database for Result Artifacts

# --- A. Check Material Receipt ---
# Look for a receipt created after start time, for Vendor Seed Farm, containing Oak Trees (qty 100)
# We join M_InOut -> M_InOutLine -> M_Product
RECEIPT_QUERY="
SELECT io.documentno, io.docstatus, iol.movementqty
FROM m_inout io
JOIN m_inoutline iol ON io.m_inout_id = iol.m_inout_id
JOIN m_product p ON iol.m_product_id = p.m_product_id
JOIN c_bpartner bp ON io.c_bpartner_id = bp.c_bpartner_id
WHERE io.issotrx='N' 
  AND io.ad_client_id=$CLIENT_ID
  AND (p.name ILIKE '%Oak Tree%' OR p.value='Oak')
  AND iol.movementqty = 100
  AND io.created >= TO_TIMESTAMP($TASK_START)
ORDER BY io.created DESC LIMIT 1;
"
RECEIPT_DATA=$(idempiere_query "$RECEIPT_QUERY" 2>/dev/null || echo "")

# Parse Receipt Data
RECEIPT_FOUND="false"
RECEIPT_DOCNO=""
RECEIPT_STATUS=""
if [ -n "$RECEIPT_DATA" ]; then
    RECEIPT_FOUND="true"
    RECEIPT_DOCNO=$(echo "$RECEIPT_DATA" | cut -d'|' -f1)
    RECEIPT_STATUS=$(echo "$RECEIPT_DATA" | cut -d'|' -f2)
fi

# --- B. Check Freight Invoice ---
# Look for invoice created after start time, amount ~250
INVOICE_QUERY="
SELECT i.documentno, i.docstatus, i.grandtotal
FROM c_invoice i
JOIN c_bpartner bp ON i.c_bpartner_id = bp.c_bpartner_id
WHERE i.issotrx='N'
  AND i.ad_client_id=$CLIENT_ID
  AND i.grandtotal = 250.00
  AND i.created >= TO_TIMESTAMP($TASK_START)
ORDER BY i.created DESC LIMIT 1;
"
INVOICE_DATA=$(idempiere_query "$INVOICE_QUERY" 2>/dev/null || echo "")

# Parse Invoice Data
INVOICE_FOUND="false"
INVOICE_DOCNO=""
INVOICE_STATUS=""
if [ -n "$INVOICE_DATA" ]; then
    INVOICE_FOUND="true"
    INVOICE_DOCNO=$(echo "$INVOICE_DATA" | cut -d'|' -f1)
    INVOICE_STATUS=$(echo "$INVOICE_DATA" | cut -d'|' -f2)
fi

# --- C. Check Landed Cost Allocation ---
# Look for an allocation record linking the invoice and the receipt
# This is the critical linkage check
ALLOCATION_QUERY="
SELECT lca.documentno, lca.processed
FROM c_landedcostallocation lca
JOIN c_invoiceline il ON lca.c_invoiceline_id = il.c_invoiceline_id
JOIN c_invoice i ON il.c_invoice_id = i.c_invoice_id
JOIN c_landedcostallocationline lcal ON lca.c_landedcostallocation_id = lcal.c_landedcostallocation_id
JOIN m_inoutline iol ON lcal.m_inoutline_id = iol.m_inoutline_id
JOIN m_inout io ON iol.m_inout_id = io.m_inout_id
WHERE lca.ad_client_id=$CLIENT_ID
  AND lca.created >= TO_TIMESTAMP($TASK_START)
  AND i.grandtotal = 250.00
  AND iol.movementqty = 100
ORDER BY lca.created DESC LIMIT 1;
"
ALLOCATION_DATA=$(idempiere_query "$ALLOCATION_QUERY" 2>/dev/null || echo "")

# Parse Allocation Data
ALLOCATION_FOUND="false"
ALLOCATION_DOCNO=""
ALLOCATION_PROCESSED="N"
if [ -n "$ALLOCATION_DATA" ]; then
    ALLOCATION_FOUND="true"
    ALLOCATION_DOCNO=$(echo "$ALLOCATION_DATA" | cut -d'|' -f1)
    ALLOCATION_PROCESSED=$(echo "$ALLOCATION_DATA" | cut -d'|' -f2)
fi

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "receipt": {
        "found": $RECEIPT_FOUND,
        "document_no": "$RECEIPT_DOCNO",
        "status": "$RECEIPT_STATUS"
    },
    "invoice": {
        "found": $INVOICE_FOUND,
        "document_no": "$INVOICE_DOCNO",
        "status": "$INVOICE_STATUS"
    },
    "allocation": {
        "found": $ALLOCATION_FOUND,
        "document_no": "$ALLOCATION_DOCNO",
        "processed": "$ALLOCATION_PROCESSED"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="