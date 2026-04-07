#!/bin/bash
# Export script for create_ap_invoice task
echo "=== Exporting create_ap_invoice Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read baseline
INITIAL_COUNT=$(cat /tmp/initial_treefarm_invoice_count 2>/dev/null || echo "0")

# Get current count of vendor invoices for Tree Farm Inc.
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE ad_client_id=11 AND c_bpartner_id=114 AND issotrx='N'")
CURRENT_COUNT=${CURRENT_COUNT:-0}

echo "Invoice count: initial=$INITIAL_COUNT current=$CURRENT_COUNT"

# Use inline Python for robust data extraction
python3 << 'PYEOF'
import subprocess, json, sys

def q(sql):
    r = subprocess.run(
        ["docker", "exec", "idempiere-postgres", "psql",
         "-U", "adempiere", "-d", "idempiere", "-t", "-A", "-c", sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# Get all vendor invoices for Tree Farm Inc. created after baseline IDs
with open("/tmp/initial_treefarm_invoice_ids") as f:
    initial_ids = set(l.strip() for l in f if l.strip().isdigit())

# Get all current invoices for Tree Farm Inc.
rows = q("""
SELECT c_invoice_id, documentno, docstatus, grandtotal
FROM c_invoice
WHERE ad_client_id=11 AND c_bpartner_id=114 AND issotrx='N'
ORDER BY c_invoice_id
""")

invoices = []
for row in rows.splitlines():
    if not row.strip():
        continue
    parts = row.split('|')
    if len(parts) >= 4:
        inv_id = parts[0].strip()
        if inv_id not in initial_ids:
            invoices.append({
                "c_invoice_id": int(inv_id),
                "documentno": parts[1].strip(),
                "docstatus": parts[2].strip(),
                "grandtotal": float(parts[3].strip() or 0)
            })

# For each new invoice, get the lines
invoice_lines = {}
for inv in invoices:
    lines_raw = q(f"""
SELECT m_product_id, qtyinvoiced, priceactual
FROM c_invoiceline
WHERE c_invoice_id={inv['c_invoice_id']}
""")
    lines = []
    for row in lines_raw.splitlines():
        if not row.strip():
            continue
        parts = row.split('|')
        if len(parts) >= 3:
            lines.append({
                "m_product_id": int(parts[0].strip() or 0),
                "qty": float(parts[1].strip() or 0),
                "price": float(parts[2].strip() or 0)
            })
    invoice_lines[inv['c_invoice_id']] = lines

result = {
    "new_invoices": invoices,
    "invoice_lines": {str(k): v for k, v in invoice_lines.items()}
}

with open("/tmp/create_ap_invoice_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Found {len(invoices)} new invoice(s)")
for inv in invoices:
    print(f"  Invoice {inv['c_invoice_id']}: status={inv['docstatus']}, total={inv['grandtotal']}")
    for line in invoice_lines.get(inv['c_invoice_id'], []):
        print(f"    Product {line['m_product_id']} qty={line['qty']} price={line['price']}")
PYEOF

echo "=== Export Complete ==="
