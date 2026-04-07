#!/bin/bash
# Export script for update_export_pricelist_and_create_order task
echo "=== Exporting update_export_pricelist_and_create_order Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read baseline prices
INITIAL=$(cat /tmp/initial_export_prices 2>/dev/null || echo "30.6900|61.3600|20.4500")
INIT_CHAIR=$(echo "$INITIAL"  | cut -d'|' -f1)
INIT_TABLE=$(echo "$INITIAL"  | cut -d'|' -f2)
INIT_SCREEN=$(echo "$INITIAL" | cut -d'|' -f3)

# Current Export 2003 prices
CHAIR_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=105 AND m_product_id=133")
TABLE_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=105 AND m_product_id=134")
SCREEN_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=105 AND m_product_id=135")

CHAIR_PRICE=${CHAIR_PRICE:-0}
TABLE_PRICE=${TABLE_PRICE:-0}
SCREEN_PRICE=${SCREEN_PRICE:-0}

echo "Current Export 2003 prices — Chair: $CHAIR_PRICE | Table: $TABLE_PRICE | Screen: $SCREEN_PRICE"

# Use Python to extract new SO data for Patio Fun Inc.
python3 << 'PYEOF'
import subprocess, json

def q(sql):
    r = subprocess.run(
        ["docker", "exec", "idempiere-postgres", "psql",
         "-U", "adempiere", "-d", "idempiere", "-t", "-A", "-c", sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# Read initial SO IDs for Patio Fun Inc.
try:
    with open("/tmp/initial_patiofun_so_ids") as f:
        initial_so_ids = set(l.strip() for l in f if l.strip().isdigit())
except:
    initial_so_ids = set()

# Get all current SOs for Patio Fun Inc. (c_bpartner_id=121)
rows = q("""
SELECT c_order_id, documentno, docstatus, m_pricelist_id
FROM c_order
WHERE ad_client_id=11 AND c_bpartner_id=121 AND issotrx='Y'
ORDER BY c_order_id
""")

new_orders = []
for row in rows.splitlines():
    if not row.strip():
        continue
    parts = row.split('|')
    if len(parts) >= 4:
        so_id = parts[0].strip()
        if so_id not in initial_so_ids:
            new_orders.append({
                "c_order_id":     int(so_id),
                "documentno":     parts[1].strip(),
                "docstatus":      parts[2].strip(),
                "m_pricelist_id": int(parts[3].strip() or 0)
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
                "qty":          float(parts[1].strip() or 0),
                "price":        float(parts[2].strip() or 0)
            })
    order_lines[so['c_order_id']] = lines

result = {
    "new_sales_orders": new_orders,
    "order_lines": {str(k): v for k, v in order_lines.items()}
}

with open("/tmp/update_export_pricelist_and_create_order_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Found {len(new_orders)} new SO(s) for Patio Fun Inc.")
for so in new_orders:
    print(f"  SO {so['c_order_id']}: status={so['docstatus']} pricelist={so['m_pricelist_id']}")
    for line in order_lines.get(so['c_order_id'], []):
        print(f"    Product {line['m_product_id']} qty={line['qty']} price={line['price']}")
PYEOF

# Append price data to the result JSON
python3 - << PYEOF2
import json

with open("/tmp/update_export_pricelist_and_create_order_result.json") as f:
    result = json.load(f)

result["current_chair_price"]  = "${CHAIR_PRICE}"
result["current_table_price"]  = "${TABLE_PRICE}"
result["current_screen_price"] = "${SCREEN_PRICE}"
result["initial_chair_price"]  = "${INIT_CHAIR}"
result["initial_table_price"]  = "${INIT_TABLE}"
result["initial_screen_price"] = "${INIT_SCREEN}"

with open("/tmp/update_export_pricelist_and_create_order_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Price data appended to result")
PYEOF2

echo "=== Export Complete ==="
