#!/bin/bash
# Export script for configure_customer_credit_and_order task
echo "=== Exporting configure_customer_credit_and_order Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read baseline
INIT_STATE=$(cat /tmp/initial_agritech_settings 2>/dev/null || echo "5000|105")
INIT_CREDIT=$(echo "$INIT_STATE" | cut -d'|' -f1)
INIT_PAYTERM=$(echo "$INIT_STATE" | cut -d'|' -f2)

# Current Agri-Tech settings
CURRENT_CREDIT=$(idempiere_query "SELECT so_creditlimit FROM c_bpartner WHERE c_bpartner_id=200000 AND ad_client_id=11")
CURRENT_PAYTERM=$(idempiere_query "SELECT c_paymentterm_id FROM c_bpartner WHERE c_bpartner_id=200000 AND ad_client_id=11")
CURRENT_CREDIT=${CURRENT_CREDIT:-0}
CURRENT_PAYTERM=${CURRENT_PAYTERM:-0}

echo "Agri-Tech — creditlimit: $CURRENT_CREDIT (was $INIT_CREDIT) | payterm: $CURRENT_PAYTERM (was $INIT_PAYTERM)"

# Use Python for SO / order line extraction
python3 << 'PYEOF'
import subprocess, json

def q(sql):
    r = subprocess.run(
        ["docker", "exec", "idempiere-postgres", "psql",
         "-U", "adempiere", "-d", "idempiere", "-t", "-A", "-c", sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# Read initial SO IDs
try:
    with open("/tmp/initial_agritech_so_ids") as f:
        initial_so_ids = set(l.strip() for l in f if l.strip().isdigit())
except:
    initial_so_ids = set()

# Get all current SOs for Agri-Tech
rows = q("""
SELECT c_order_id, documentno, docstatus
FROM c_order
WHERE ad_client_id=11 AND c_bpartner_id=200000 AND issotrx='Y'
ORDER BY c_order_id
""")

new_orders = []
for row in rows.splitlines():
    if not row.strip():
        continue
    parts = row.split('|')
    if len(parts) >= 3:
        so_id = parts[0].strip()
        if so_id not in initial_so_ids:
            new_orders.append({
                "c_order_id": int(so_id),
                "documentno": parts[1].strip(),
                "docstatus": parts[2].strip()
            })

# Get order lines for each new SO
order_lines = {}
for so in new_orders:
    lines_raw = q(f"""
SELECT m_product_id, qtyordered, priceactual
FROM c_orderline
WHERE c_order_id={so['c_order_id']}
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
    order_lines[so['c_order_id']] = lines

result = {
    "new_sales_orders": new_orders,
    "order_lines": {str(k): v for k, v in order_lines.items()}
}

with open("/tmp/configure_customer_credit_and_order_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Found {len(new_orders)} new SO(s) for Agri-Tech")
for so in new_orders:
    print(f"  SO {so['c_order_id']}: status={so['docstatus']}")
    for line in order_lines.get(so['c_order_id'], []):
        print(f"    Product {line['m_product_id']} qty={line['qty']}")
PYEOF

# Append the BP settings to the result JSON
python3 - << PYEOF2
import json, sys

with open("/tmp/configure_customer_credit_and_order_result.json") as f:
    result = json.load(f)

result["current_credit_limit"] = "${CURRENT_CREDIT}"
result["current_payterm_id"]   = "${CURRENT_PAYTERM}"
result["initial_credit_limit"] = "${INIT_CREDIT}"
result["initial_payterm_id"]   = "${INIT_PAYTERM}"

with open("/tmp/configure_customer_credit_and_order_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("BP settings appended to result")
PYEOF2

echo "=== Export Complete ==="
