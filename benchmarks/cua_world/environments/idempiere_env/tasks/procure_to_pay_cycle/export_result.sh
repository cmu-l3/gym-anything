#!/bin/bash
set -e
echo "=== Exporting procure_to_pay_cycle results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Use Python for robust multi-table JSON construction
# Using non-quoted heredoc so $TASK_START and $CLIENT_ID are expanded by the shell
python3 << PYEOF
import subprocess
import json

def db_query(sql):
    """Run a psql query inside the Docker container."""
    try:
        result = subprocess.run(
            ["docker", "exec", "idempiere-postgres", "psql",
             "-U", "adempiere", "-d", "idempiere", "-t", "-A", "-c", sql],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip()
    except Exception:
        return ""

task_start = $TASK_START
client_id = $CLIENT_ID

# --- A. Check Purchase Order ---
po_data = db_query("""
SELECT row_to_json(t) FROM (
    SELECT o.c_order_id, o.documentno, o.grandtotal, o.docstatus,
        (SELECT json_agg(row_to_json(l)) FROM (
            SELECT ol.m_product_id, p.name as product_name,
                   ol.qtyordered, ol.priceactual, ol.linenetamt
            FROM c_orderline ol
            JOIN m_product p ON ol.m_product_id = p.m_product_id
            WHERE ol.c_order_id = o.c_order_id
        ) l) as order_lines
    FROM c_order o
    JOIN c_bpartner bp ON o.c_bpartner_id = bp.c_bpartner_id
    WHERE bp.name = 'Tree Farm Inc.'
      AND o.issotrx = 'N'
      AND o.ad_client_id = """ + str(client_id) + """
      AND o.created >= to_timestamp(""" + str(task_start) + """)
    ORDER BY o.created DESC
    LIMIT 1
) t;
""")

# --- B. Check Material Receipt ---
receipt_data = db_query("""
SELECT row_to_json(t) FROM (
    SELECT io.m_inout_id, io.documentno, io.docstatus,
        (SELECT json_agg(row_to_json(l)) FROM (
            SELECT iol.m_product_id, p.name as product_name,
                   iol.movementqty
            FROM m_inoutline iol
            JOIN m_product p ON iol.m_product_id = p.m_product_id
            WHERE iol.m_inout_id = io.m_inout_id
        ) l) as receipt_lines
    FROM m_inout io
    JOIN c_bpartner bp ON io.c_bpartner_id = bp.c_bpartner_id
    WHERE bp.name = 'Tree Farm Inc.'
      AND io.issotrx = 'N'
      AND io.ad_client_id = """ + str(client_id) + """
      AND io.created >= to_timestamp(""" + str(task_start) + """)
    ORDER BY io.created DESC
    LIMIT 1
) t;
""")

# --- C. Check Vendor Invoice ---
invoice_data = db_query("""
SELECT row_to_json(t) FROM (
    SELECT i.c_invoice_id, i.documentno, i.grandtotal, i.docstatus, i.ispaid,
        (SELECT json_agg(row_to_json(l)) FROM (
            SELECT il.m_product_id, p.name as product_name,
                   il.qtyinvoiced, il.priceactual, il.linenetamt
            FROM c_invoiceline il
            JOIN m_product p ON il.m_product_id = p.m_product_id
            WHERE il.c_invoice_id = i.c_invoice_id
        ) l) as invoice_lines
    FROM c_invoice i
    JOIN c_bpartner bp ON i.c_bpartner_id = bp.c_bpartner_id
    WHERE bp.name = 'Tree Farm Inc.'
      AND i.issotrx = 'N'
      AND i.ad_client_id = """ + str(client_id) + """
      AND i.created >= to_timestamp(""" + str(task_start) + """)
    ORDER BY i.created DESC
    LIMIT 1
) t;
""")

# --- D. Check Payment ---
payment_data = db_query("""
SELECT row_to_json(t) FROM (
    SELECT p.c_payment_id, p.documentno, p.payamt, p.checkno,
           p.docstatus, p.isallocated
    FROM c_payment p
    JOIN c_bpartner bp ON p.c_bpartner_id = bp.c_bpartner_id
    WHERE bp.name = 'Tree Farm Inc.'
      AND p.isreceipt = 'N'
      AND p.ad_client_id = """ + str(client_id) + """
      AND p.created >= to_timestamp(""" + str(task_start) + """)
    ORDER BY p.created DESC
    LIMIT 1
) t;
""")

# --- E. Check Allocation ---
allocation_found = False
allocation_status = ""

try:
    inv_obj = json.loads(invoice_data) if invoice_data else {}
    pay_obj = json.loads(payment_data) if payment_data else {}
    inv_id = inv_obj.get('c_invoice_id')
    pay_id = pay_obj.get('c_payment_id')
    if inv_id and pay_id:
        alloc_result = db_query(
            "SELECT ah.docstatus FROM c_allocationline al "
            "JOIN c_allocationhdr ah ON al.c_allocationhdr_id = ah.c_allocationhdr_id "
            "WHERE al.c_invoice_id = " + str(inv_id) +
            " AND al.c_payment_id = " + str(pay_id) +
            " AND ah.ad_client_id = " + str(client_id) +
            " AND ah.docstatus IN ('CO', 'CL') LIMIT 1;"
        )
        if alloc_result:
            allocation_found = True
            allocation_status = alloc_result
except Exception:
    pass

# Build final result
result = {
    "task_start": task_start,
    "purchase_order": json.loads(po_data) if po_data else None,
    "material_receipt": json.loads(receipt_data) if receipt_data else None,
    "vendor_invoice": json.loads(invoice_data) if invoice_data else None,
    "payment": json.loads(payment_data) if payment_data else None,
    "allocation_found": allocation_found,
    "allocation_status": allocation_status,
}

with open("/tmp/procure_to_pay_cycle_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Copy to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/procure_to_pay_cycle_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json
