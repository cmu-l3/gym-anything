#!/bin/bash
# Export script for Lot Tracking Receipt & Delivery task

echo "=== Exporting Lot Tracking Receipt & Delivery Result ==="

source /workspace/scripts/task_utils.sh

if ! type odoo_query &>/dev/null; then
    odoo_query() {
        docker exec odoo-postgres psql -U odoo -d odoo_inventory -t -A -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/lot_tracking_receipt_delivery_end.png

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
    'task': 'lot_tracking_receipt_delivery',
    'task_start': task_start,
    'products': {},
}

# Check product tracking settings
for code in ['LOT-TRACK-001', 'LOT-TRACK-002', 'LOT-TRACK-003']:
    tracking_data = odoo_query(f"""
        SELECT pt.tracking, pt.name
        FROM product_template pt
        WHERE pt.default_code = '{code}'
        LIMIT 1
    """)
    if tracking_data:
        parts = tracking_data.split('|')
        tracking = parts[0].strip() if parts else 'none'
        name = parts[1].strip() if len(parts) > 1 else ''
        result['products'][code] = {
            'tracking': tracking,
            'name': name,
            'tracking_enabled': tracking == 'lot',
        }
        print(f"{code}: tracking={tracking}")
    else:
        result['products'][code] = {'tracking': 'unknown', 'tracking_enabled': False}
        print(f"{code}: not found")

# Find the PO and its receipt
vendor_id_data = odoo_query("""
    SELECT id FROM res_partner WHERE name = 'Medline Industries Inc.' LIMIT 1
""")
vendor_id = int(vendor_id_data.strip()) if vendor_id_data and vendor_id_data.strip().isdigit() else None

result['vendor_id'] = vendor_id

po_data = None
picking_id = None
picking_state = 'unknown'

if vendor_id:
    # Find the most recent confirmed PO for this vendor
    po_data = odoo_query(f"""
        SELECT po.id, po.name, po.state
        FROM purchase_order po
        WHERE po.partner_id = {vendor_id}
        AND po.state IN ('purchase', 'done')
        ORDER BY po.id DESC
        LIMIT 1
    """)

if po_data:
    parts = po_data.split('|')
    po_id = int(parts[0].strip()) if parts[0].strip() else None
    po_name = parts[1].strip() if len(parts) > 1 else ''
    po_state = parts[2].strip() if len(parts) > 2 else ''
    result['po_id'] = po_id
    result['po_name'] = po_name
    result['po_state'] = po_state
    print(f"PO: {po_name} (state={po_state}, id={po_id})")

    # Find the receipt picking for this PO
    picking_data = odoo_query(f"""
        SELECT sp.id, sp.name, sp.state
        FROM stock_picking sp
        JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
        WHERE sp.purchase_id = {po_id}
        AND spt.code = 'incoming'
        ORDER BY sp.id DESC
        LIMIT 1
    """)
    if picking_data:
        parts = picking_data.split('|')
        picking_id = int(parts[0].strip()) if parts[0].strip() else None
        picking_name = parts[1].strip() if len(parts) > 1 else ''
        picking_state = parts[2].strip() if len(parts) > 2 else ''
        result['picking_id'] = picking_id
        result['picking_name'] = picking_name
        result['picking_state'] = picking_state
        result['receipt_validated'] = picking_state == 'done'
        print(f"Receipt: {picking_name} (state={picking_state})")
    else:
        result['picking_id'] = None
        result['picking_state'] = 'not_found'
        result['receipt_validated'] = False
        print("No receipt picking found")
else:
    result['po_id'] = None
    result['po_name'] = ''
    result['po_state'] = 'not_found'
    result['picking_id'] = None
    result['picking_state'] = 'not_found'
    result['receipt_validated'] = False
    print("No PO found for Medline Industries Inc.")

# Check lot numbers assigned in stock move lines
if picking_id and picking_state == 'done':
    for code, expected_lot, expected_qty in [
        ('LOT-TRACK-001', 'MED-2024-AB-001', 200),
        ('LOT-TRACK-002', 'MED-2024-BR-001', 150),
        ('LOT-TRACK-003', 'MED-2024-3M-001', 300),
    ]:
        lot_data = odoo_query(f"""
            SELECT sl.name as lot_name, COALESCE(SUM(sml.qty_done), 0)::float as qty_done
            FROM stock_move_line sml
            JOIN stock_move sm ON sml.move_id = sm.id
            JOIN product_product pp ON sml.product_id = pp.id
            JOIN product_template pt ON pp.product_tmpl_id = pt.id
            LEFT JOIN stock_lot sl ON sml.lot_id = sl.id
            WHERE sm.picking_id = {picking_id}
            AND pt.default_code = '{code}'
            GROUP BY sl.name
            ORDER BY qty_done DESC
            LIMIT 1
        """)
        if lot_data:
            parts = lot_data.split('|')
            lot_name = parts[0].strip() if parts else ''
            qty_done = float(parts[1].strip()) if len(parts) > 1 and parts[1].strip() else 0.0
            correct_lot = lot_name == expected_lot
            correct_qty = abs(qty_done - expected_qty) < 0.5
            result['products'][code]['lot_received'] = lot_name
            result['products'][code]['qty_received'] = qty_done
            result['products'][code]['correct_lot'] = correct_lot
            result['products'][code]['correct_qty'] = correct_qty
            print(f"  {code}: lot={lot_name!r} (expected {expected_lot!r}), qty={qty_done} (expected {expected_qty})")
        else:
            result['products'][code]['lot_received'] = ''
            result['products'][code]['qty_received'] = 0.0
            result['products'][code]['correct_lot'] = False
            result['products'][code]['correct_qty'] = False
            print(f"  {code}: no move lines found")
else:
    # Receipt not done — check if any lots were at least created
    for code in ['LOT-TRACK-001', 'LOT-TRACK-002', 'LOT-TRACK-003']:
        result['products'][code]['lot_received'] = ''
        result['products'][code]['qty_received'] = 0.0
        result['products'][code]['correct_lot'] = False
        result['products'][code]['correct_qty'] = False

with open('/tmp/lot_tracking_receipt_delivery_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("\nExport complete.")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
