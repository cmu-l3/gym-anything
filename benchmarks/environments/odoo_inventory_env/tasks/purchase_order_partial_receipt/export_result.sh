#!/bin/bash
# Export script for Purchase Order Partial Receipt task

echo "=== Exporting Purchase Order Partial Receipt Result ==="

source /workspace/scripts/task_utils.sh

if ! type odoo_query &>/dev/null; then
    odoo_query() {
        docker exec odoo-postgres psql -U odoo -d odoo_inventory -t -A -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/purchase_order_partial_receipt_end.png

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
    'task': 'purchase_order_partial_receipt',
    'task_start': task_start,
    'products': {},
}

# For each product, find all POs created after task start and their receipt status
# Correct vendor choices:
# ELEC-COMP-001 -> Automation Parts Direct (3.42)
# ELEC-COMP-002 -> Component World (1.87)
# ELEC-COMP-003 -> Component World (7.95)

expected_data = {
    'ELEC-COMP-001': {
        'cheapest_vendor': 'Automation Parts Direct',
        'total_qty': 100,
        'partial_qty': 40,
        'backorder_expected': True,
    },
    'ELEC-COMP-002': {
        'cheapest_vendor': 'Component World',
        'total_qty': 200,
        'partial_qty': 200,
        'backorder_expected': False,
    },
    'ELEC-COMP-003': {
        'cheapest_vendor': 'Component World',
        'total_qty': 1000,
        'partial_qty': 600,
        'backorder_expected': True,
    },
}

for code, expected in expected_data.items():
    # Find POs for this product created after task start
    po_data = odoo_query(f"""
        SELECT po.id, po.name, po.state, rp.name as vendor_name, pol.price_unit,
               pol.product_qty
        FROM purchase_order po
        JOIN purchase_order_line pol ON pol.order_id = po.id
        JOIN product_product pp ON pol.product_id = pp.id
        JOIN product_template pt ON pp.product_tmpl_id = pt.id
        JOIN res_partner rp ON po.partner_id = rp.id
        WHERE pt.default_code = '{code}'
        AND EXTRACT(EPOCH FROM po.create_date)::bigint > {task_start}
        AND po.state NOT IN ('cancel')
        ORDER BY po.id DESC
        LIMIT 1
    """)

    if po_data:
        parts = po_data.split('|')
        po_id = int(parts[0].strip()) if parts[0].strip() else None
        po_name = parts[1].strip() if len(parts) > 1 else ''
        po_state = parts[2].strip() if len(parts) > 2 else ''
        vendor_name = parts[3].strip() if len(parts) > 3 else ''
        price_unit = float(parts[4].strip()) if len(parts) > 4 and parts[4].strip() else 0.0
        ordered_qty = float(parts[5].strip()) if len(parts) > 5 and parts[5].strip() else 0.0

        correct_vendor = vendor_name == expected['cheapest_vendor']

        result['products'][code] = {
            'po_id': po_id,
            'po_name': po_name,
            'po_state': po_state,
            'vendor_name': vendor_name,
            'price_unit': price_unit,
            'ordered_qty': ordered_qty,
            'correct_vendor': correct_vendor,
        }
        print(f"{code}: PO={po_name}, vendor={vendor_name!r} ({'✓' if correct_vendor else '✗'} expected {expected['cheapest_vendor']!r})")

        # Find the receipt (incoming picking) for this PO
        picking_data = odoo_query(f"""
            SELECT sp.id, sp.name, sp.state, sp.backorder_id
            FROM stock_picking sp
            JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
            WHERE sp.purchase_id = {po_id}
            AND spt.code = 'incoming'
            ORDER BY sp.id ASC
        """)

        pickings = []
        if picking_data:
            for row in picking_data.strip().split('\n'):
                if not row.strip():
                    continue
                p = row.split('|')
                if len(p) >= 3:
                    pickings.append({
                        'id': int(p[0].strip()) if p[0].strip() else None,
                        'name': p[1].strip(),
                        'state': p[2].strip(),
                        'backorder_id': p[3].strip() if len(p) > 3 else None,
                    })

        result['products'][code]['pickings'] = pickings
        done_pickings = [p for p in pickings if p['state'] == 'done']
        has_done_receipt = len(done_pickings) > 0

        # Check backorder: a backorder exists if there's a picking with backorder_id referencing another
        has_backorder = any(
            p.get('backorder_id') and p['backorder_id'] not in ('', 'None', None)
            for p in pickings
        )
        # Also check if any picking is a backorder (has a non-null backorder_id)
        if not has_backorder and len(pickings) > 1:
            # Multiple pickings for same PO usually means backorder was created
            has_backorder = True

        result['products'][code]['has_done_receipt'] = has_done_receipt
        result['products'][code]['has_backorder'] = has_backorder
        print(f"  Pickings: {len(pickings)}, done: {len(done_pickings)}, backorder: {has_backorder}")

        # Check quantity received
        if done_pickings:
            for done_p in done_pickings:
                qty_done = odoo_query(f"""
                    SELECT COALESCE(SUM(sml.qty_done), 0)::float
                    FROM stock_move_line sml
                    JOIN stock_move sm ON sml.move_id = sm.id
                    JOIN product_product pp ON sml.product_id = pp.id
                    JOIN product_template pt ON pp.product_tmpl_id = pt.id
                    WHERE sm.picking_id = {done_p['id']}
                    AND pt.default_code = '{code}'
                """)
                qty = float(qty_done) if qty_done else 0.0
                result['products'][code]['qty_received'] = qty
                print(f"  Qty received in done picking: {qty}")
                break
        else:
            result['products'][code]['qty_received'] = 0.0

    else:
        result['products'][code] = {
            'po_id': None,
            'po_name': '',
            'vendor_name': '',
            'correct_vendor': False,
            'has_done_receipt': False,
            'has_backorder': False,
            'qty_received': 0.0,
            'pickings': [],
        }
        print(f"{code}: No PO found after task start")

with open('/tmp/purchase_order_partial_receipt_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("\nExport complete.")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
