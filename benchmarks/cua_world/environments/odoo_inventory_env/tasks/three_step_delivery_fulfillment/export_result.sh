#!/bin/bash
# Export script for Three-Step Delivery Fulfillment task

echo "=== Exporting Three-Step Delivery Fulfillment Result ==="

source /workspace/scripts/task_utils.sh

if ! type odoo_query &>/dev/null; then
    odoo_query() {
        docker exec odoo-postgres psql -U odoo -d odoo_inventory -t -A -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/three_step_delivery_fulfillment_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

python3 << PYEOF
import subprocess, json

def odoo_query(sql):
    r = subprocess.run(
        ['docker', 'exec', 'odoo-postgres', 'psql', '-U', 'odoo', '-d', 'odoo_inventory',
         '-t', '-A', '-c', sql],
        capture_output=True, text=True)
    return r.stdout.strip()

task_start = $TASK_START

result = {
    'task': 'three_step_delivery_fulfillment',
    'task_start': task_start,
}

# Check warehouse delivery_steps
wh_data = odoo_query("SELECT id, name, delivery_steps FROM stock_warehouse ORDER BY id LIMIT 1")
if wh_data:
    parts = wh_data.split('|')
    result['warehouse_id'] = int(parts[0].strip()) if parts[0].strip() else None
    result['warehouse_name'] = parts[1].strip() if len(parts) > 1 else ''
    result['delivery_steps'] = parts[2].strip() if len(parts) > 2 else 'ship_only'
else:
    result['warehouse_id'] = None
    result['delivery_steps'] = 'unknown'

print(f"Warehouse delivery_steps: {result.get('delivery_steps')}")

# Find sales orders for TechSource Procurement LLC created after task start
so_data = odoo_query(f"""
    SELECT so.id, so.name, so.state
    FROM sale_order so
    JOIN res_partner rp ON so.partner_id = rp.id
    WHERE rp.name = 'TechSource Procurement LLC'
    AND EXTRACT(EPOCH FROM so.create_date)::bigint > {task_start}
    ORDER BY so.id DESC
    LIMIT 1
""")
if so_data:
    parts = so_data.split('|')
    result['so_id'] = int(parts[0].strip()) if parts[0].strip() else None
    result['so_name'] = parts[1].strip() if len(parts) > 1 else ''
    result['so_state'] = parts[2].strip() if len(parts) > 2 else ''
    print(f"Found SO: {result['so_name']} (state={result['so_state']})")
else:
    result['so_id'] = None
    result['so_name'] = ''
    result['so_state'] = ''
    print("No SO found for TechSource Procurement LLC")

so_id = result.get('so_id')

# Find pickings related to the SO
if so_id:
    pickings_data = odoo_query(f"""
        SELECT sp.id, sp.name, sp.state, spt.code, spt.name as type_name
        FROM stock_picking sp
        JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
        WHERE sp.sale_id = {so_id}
        ORDER BY sp.id
    """)
    pickings = []
    if pickings_data:
        for row in pickings_data.strip().split('\n'):
            if not row.strip():
                continue
            parts = row.split('|')
            if len(parts) >= 3:
                pickings.append({
                    'id': int(parts[0].strip()) if parts[0].strip() else None,
                    'name': parts[1].strip(),
                    'state': parts[2].strip(),
                    'type_code': parts[3].strip() if len(parts) > 3 else '',
                    'type_name': parts[4].strip() if len(parts) > 4 else '',
                })
    result['pickings'] = pickings
    result['picking_count'] = len(pickings)
    result['done_pickings'] = sum(1 for p in pickings if p['state'] == 'done')
    result['pick_op_done'] = any(
        p['state'] == 'done' and ('pick' in p.get('type_name', '').lower() or
                                   'pick' in p.get('name', '').lower())
        for p in pickings
    )
    result['pack_op_done'] = any(
        p['state'] == 'done' and ('pack' in p.get('type_name', '').lower() or
                                   'pack' in p.get('name', '').lower())
        for p in pickings
    )
    result['ship_op_done'] = any(
        p['state'] == 'done' and p.get('type_code') == 'outgoing'
        for p in pickings
    )
    print(f"Pickings: {len(pickings)}, done: {result['done_pickings']}")
    print(f"  Pick done: {result['pick_op_done']}")
    print(f"  Pack done: {result['pack_op_done']}")
    print(f"  Ship done: {result['ship_op_done']}")
else:
    result['pickings'] = []
    result['picking_count'] = 0
    result['done_pickings'] = 0
    result['pick_op_done'] = False
    result['pack_op_done'] = False
    result['ship_op_done'] = False

# Check quantities actually moved
if so_id:
    qty_moved_data = odoo_query(f"""
        SELECT COALESCE(SUM(sml.qty_done), 0)::float
        FROM stock_move_line sml
        JOIN stock_move sm ON sml.move_id = sm.id
        JOIN stock_picking sp ON sm.picking_id = sp.id
        JOIN product_product pp ON sml.product_id = pp.id
        JOIN product_template pt ON pp.product_tmpl_id = pt.id
        WHERE sp.sale_id = {so_id}
        AND sp.state = 'done'
        AND spt_check.code = 'outgoing'
        FROM stock_picking_type spt_check
        WHERE spt_check.id = sp.picking_type_id
    """) if False else odoo_query(f"""
        SELECT COALESCE(SUM(sml.qty_done), 0)::float
        FROM stock_move_line sml
        JOIN stock_move sm ON sml.move_id = sm.id
        JOIN stock_picking sp ON sm.picking_id = sp.id
        JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
        WHERE sp.sale_id = {so_id}
        AND sp.state = 'done'
        AND spt.code = 'outgoing'
    """)
    result['total_qty_shipped'] = float(qty_moved_data) if qty_moved_data else 0.0
    print(f"Total qty shipped (outgoing done): {result['total_qty_shipped']}")

    # Check individual product quantities
    for code, expected_qty in [('3STEP-001', 20), ('3STEP-002', 15), ('3STEP-003', 10)]:
        qty = odoo_query(f"""
            SELECT COALESCE(SUM(sml.qty_done), 0)::float
            FROM stock_move_line sml
            JOIN stock_move sm ON sml.move_id = sm.id
            JOIN stock_picking sp ON sm.picking_id = sp.id
            JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
            JOIN product_product pp ON sml.product_id = pp.id
            JOIN product_template pt ON pp.product_tmpl_id = pt.id
            WHERE sp.sale_id = {so_id}
            AND sp.state = 'done'
            AND spt.code = 'outgoing'
            AND pt.default_code = '{code}'
        """)
        result[f'qty_shipped_{code}'] = float(qty) if qty else 0.0

with open('/tmp/three_step_delivery_fulfillment_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("\nExport complete.")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
