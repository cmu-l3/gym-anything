#!/bin/bash
# Export script for Inventory Discrepancy Audit task

echo "=== Exporting Inventory Discrepancy Audit Result ==="

source /workspace/scripts/task_utils.sh

if ! type odoo_query &>/dev/null; then
    odoo_query() {
        docker exec odoo-postgres psql -U odoo -d odoo_inventory -t -A -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/inventory_discrepancy_audit_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

python3 << 'PYEOF'
import subprocess, json, sys, os

def odoo_query(sql):
    result = subprocess.run(
        ['docker', 'exec', 'odoo-postgres', 'psql', '-U', 'odoo', '-d', 'odoo_inventory',
         '-t', '-A', '-c', sql],
        capture_output=True, text=True
    )
    return result.stdout.strip()

# Get WH/Stock location
stock_loc_id = odoo_query(
    "SELECT id FROM stock_location WHERE usage='internal' AND complete_name LIKE '%/Stock' ORDER BY id LIMIT 1"
)
if not stock_loc_id:
    stock_loc_id = odoo_query(
        "SELECT id FROM stock_location WHERE usage='internal' AND name='Stock' ORDER BY id LIMIT 1"
    )
print(f"Stock location ID: {stock_loc_id}")

task_start = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

# Expected quantities per physical count sheet
expected = {
    'INV-AUDIT-001': 45.0,
    'INV-AUDIT-002': 12.0,
    'INV-AUDIT-003': 18.0,
    'INV-AUDIT-004': 0.0,
    'INV-AUDIT-005': 50.0,
    'INV-AUDIT-006': 7.0,
}
# Initial (wrong) system quantities
initial = {
    'INV-AUDIT-001': 8.0,
    'INV-AUDIT-002': 3.0,
    'INV-AUDIT-003': 22.0,
    'INV-AUDIT-004': 15.0,
    'INV-AUDIT-005': 33.0,
    'INV-AUDIT-006': 7.0,
}

result = {
    'task': 'inventory_discrepancy_audit',
    'task_start': task_start,
    'stock_loc_id': int(stock_loc_id) if stock_loc_id else 0,
    'products': {},
}

for code, exp_qty in expected.items():
    # First check if the product actually exists in the DB
    product_exists_str = odoo_query(f"""
        SELECT COUNT(*) FROM product_template WHERE default_code = '{code}'
    """)
    product_exists = int(product_exists_str) > 0 if product_exists_str else False

    # Query current quantity in WH/Stock
    qty_str = odoo_query(f"""
        SELECT COALESCE(SUM(sq.quantity), 0)::float
        FROM stock_quant sq
        JOIN product_product pp ON sq.product_id = pp.id
        JOIN product_template pt ON pp.product_tmpl_id = pt.id
        WHERE pt.default_code = '{code}'
        AND sq.location_id = {stock_loc_id or 0}
    """)
    current_qty = float(qty_str) if qty_str else 0.0

    # Also check all internal locations combined
    all_qty_str = odoo_query(f"""
        SELECT COALESCE(SUM(sq.quantity), 0)::float
        FROM stock_quant sq
        JOIN product_product pp ON sq.product_id = pp.id
        JOIN product_template pt ON pp.product_tmpl_id = pt.id
        WHERE pt.default_code = '{code}'
        AND sq.location_id IN (SELECT id FROM stock_location WHERE usage='internal')
    """)
    all_internal_qty = float(all_qty_str) if all_qty_str else 0.0

    init_qty = initial[code]
    matches = product_exists and abs(current_qty - exp_qty) < 0.5
    # was_changed: only meaningful if product exists; avoid false positives when product absent
    was_changed = product_exists and abs(current_qty - init_qty) > 0.1

    result['products'][code] = {
        'expected_qty': exp_qty,
        'initial_qty': init_qty,
        'current_qty': current_qty,
        'all_internal_qty': all_internal_qty,
        'product_exists': product_exists,
        'matches_expected': matches,
        'was_changed': was_changed,
    }
    print(f"{code}: exists={product_exists}, init={init_qty}, expected={exp_qty}, current={current_qty}, match={matches}")

# Count how many inventory adjustment moves were done after task start
inv_move_count_str = odoo_query(f"""
    SELECT COUNT(DISTINCT sm.id)
    FROM stock_move sm
    WHERE sm.state = 'done'
    AND sm.reference LIKE '%Inventory%'
    AND EXTRACT(EPOCH FROM sm.write_date)::bigint > {task_start}
""")
inv_move_count = int(inv_move_count_str) if inv_move_count_str else 0

# Also check quant write_dates to detect changes made by agent
quant_changes_str = odoo_query(f"""
    SELECT COUNT(*)
    FROM stock_quant sq
    JOIN product_product pp ON sq.product_id = pp.id
    JOIN product_template pt ON pp.product_tmpl_id = pt.id
    WHERE pt.default_code LIKE 'INV-AUDIT-%'
    AND EXTRACT(EPOCH FROM sq.write_date)::bigint > {task_start}
""")
quant_changes = int(quant_changes_str) if quant_changes_str else 0

result['inventory_moves_count'] = inv_move_count
result['quant_changes_after_start'] = quant_changes

with open('/tmp/inventory_discrepancy_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("\n=== Result Summary ===")
correct = sum(1 for v in result['products'].values() if v['matches_expected'])
print(f"Products with correct quantity: {correct}/6")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
