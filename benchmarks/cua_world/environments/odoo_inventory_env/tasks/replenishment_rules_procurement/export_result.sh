#!/bin/bash
# Export script for Replenishment Rules Procurement task

echo "=== Exporting Replenishment Rules Procurement Result ==="

source /workspace/scripts/task_utils.sh

if ! type odoo_query &>/dev/null; then
    odoo_query() {
        docker exec odoo-postgres psql -U odoo -d odoo_inventory -t -A -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/replenishment_rules_procurement_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_PO_COUNT=$(cat /tmp/initial_po_count 2>/dev/null || echo "0")

python3 << PYEOF
import subprocess, json, sys

def odoo_query(sql):
    r = subprocess.run(
        ['docker', 'exec', 'odoo-postgres', 'psql', '-U', 'odoo', '-d', 'odoo_inventory',
         '-t', '-A', '-c', sql],
        capture_output=True, text=True)
    return r.stdout.strip()

task_start = $TASK_START
initial_po_count = $INITIAL_PO_COUNT

low_stock_skus = ['REPR-001', 'REPR-002', 'REPR-003', 'REPR-004', 'REPR-005']
high_stock_skus = ['REPR-006', 'REPR-007']
all_skus = low_stock_skus + high_stock_skus

result = {
    'task': 'replenishment_rules_procurement',
    'task_start': task_start,
    'initial_po_count': initial_po_count,
    'reorder_rules': {},
    'current_pos': {},
}

# Check reorder rules for each product
for code in all_skus:
    rule_data = odoo_query(f"""
        SELECT op.id, op.product_min_qty, op.product_max_qty, op.qty_multiple, op.warehouse_id
        FROM stock_warehouse_orderpoint op
        JOIN product_product pp ON op.product_id = pp.id
        JOIN product_template pt ON pp.product_tmpl_id = pt.id
        WHERE pt.default_code = '{code}'
        AND op.active = true
        LIMIT 1
    """)
    if rule_data:
        parts = rule_data.split('|')
        result['reorder_rules'][code] = {
            'exists': True,
            'rule_id': int(parts[0].strip()) if parts[0].strip() else None,
            'min_qty': float(parts[1].strip()) if len(parts) > 1 and parts[1].strip() else 0,
            'max_qty': float(parts[2].strip()) if len(parts) > 2 and parts[2].strip() else 0,
        }
    else:
        result['reorder_rules'][code] = {'exists': False}

# Count new purchase orders created after task start
new_po_count_str = odoo_query(f"""
    SELECT COUNT(*) FROM purchase_order
    WHERE EXTRACT(EPOCH FROM create_date)::bigint > {task_start}
""")
new_po_count = int(new_po_count_str) if new_po_count_str else 0
result['new_po_count'] = new_po_count

# Check if procurement orders were generated (stock.route or purchase orders)
procurement_orders = odoo_query(f"""
    SELECT COUNT(*) FROM purchase_order_line pol
    JOIN purchase_order po ON pol.order_id = po.id
    JOIN product_product pp ON pol.product_id = pp.id
    JOIN product_template pt ON pp.product_tmpl_id = pt.id
    WHERE pt.default_code LIKE 'REPR-%'
    AND EXTRACT(EPOCH FROM po.create_date)::bigint > {task_start}
""")
result['procurement_lines_for_repr'] = int(procurement_orders) if procurement_orders else 0

# Also check for stock move rules or procurement moves
proc_moves = odoo_query(f"""
    SELECT COUNT(*) FROM stock_move sm
    JOIN product_product pp ON sm.product_id = pp.id
    JOIN product_template pt ON pp.product_tmpl_id = pt.id
    WHERE pt.default_code LIKE 'REPR-%'
    AND sm.state NOT IN ('cancel', 'draft')
    AND EXTRACT(EPOCH FROM sm.create_date)::bigint > {task_start}
""")
result['procurement_stock_moves'] = int(proc_moves) if proc_moves else 0

print(f"Reorder rules created: {sum(1 for v in result['reorder_rules'].values() if v.get('exists'))}")
print(f"New POs after task start: {new_po_count}")
print(f"Procurement lines for REPR products: {result['procurement_lines_for_repr']}")

with open('/tmp/replenishment_rules_procurement_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Export done.")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
