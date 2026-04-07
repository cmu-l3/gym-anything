#!/bin/bash
# Export script for smartdesk_product_launch_validation
# Queries Odoo to verify: product template with variants, BOMs,
# pricelist, manufacturing order, and sales order state.

echo "=== Exporting smartdesk_product_launch_validation results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check setup data exists
if [ ! -f /tmp/smartdesk_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null || true
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin'
PASSWORD = 'admin'

# Load setup data
with open('/tmp/smartdesk_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/smartdesk_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

result = {
    'task': 'smartdesk_product_launch_validation',
    'export_timestamp': datetime.now().isoformat(),
}

comp_prod_ids = setup.get('component_product_ids', {})
customer_id = setup.get('customer_id')

# ─── 1. Product Template: SmartDesk Pro ───────────────────────────────────────
PRODUCT_NAME = 'SmartDesk Pro'

templates = execute('product.template', 'search_read',
    [[['name', 'ilike', PRODUCT_NAME]]],
    {'fields': ['id', 'name', 'list_price', 'standard_price', 'attribute_line_ids'],
     'order': 'id desc', 'limit': 1})

template_id = None
ptavs = {}  # name -> ptav_id mapping

if templates:
    tmpl = templates[0]
    template_id = tmpl['id']

    # Read attribute lines to get attributes, values, and PTAVs
    attr_lines = execute('product.template.attribute.line', 'search_read',
        [[['product_tmpl_id', '=', template_id]]],
        {'fields': ['attribute_id', 'value_ids', 'product_template_value_ids']})

    attributes_found = {}
    price_extras = {}

    for line in attr_lines:
        attr_name = line['attribute_id'][1] if isinstance(line['attribute_id'], list) else ''

        # Get value names
        values = execute('product.attribute.value', 'read',
            [line['value_ids']], {'fields': ['name']})
        value_names = [v['name'] for v in values]
        attributes_found[attr_name] = value_names

        # Get PTAVs with price extras
        ptav_records = execute('product.template.attribute.value', 'read',
            line['product_template_value_ids'],
            ['name', 'price_extra', 'product_attribute_value_id'])
        for ptav in ptav_records:
            ptavs[ptav['name']] = ptav['id']
            if ptav['price_extra'] != 0.0:
                price_extras[ptav['name']] = ptav['price_extra']

    # Count variants
    variant_count = execute('product.product', 'search_count',
        [[['product_tmpl_id', '=', template_id]]])

    result['product_template'] = {
        'found': True,
        'id': template_id,
        'name': tmpl['name'],
        'list_price': tmpl['list_price'],
        'attributes': attributes_found,
        'price_extras': price_extras,
        'variant_count': variant_count,
        'ptavs': ptavs,
    }
    print(f"Found product template: {tmpl['name']} (id={template_id}), {variant_count} variants")
else:
    result['product_template'] = {'found': False}
    print("Product template 'SmartDesk Pro' NOT found.")

# ─── 2. Sub-Assembly BOM: Motorized Lift Frame ───────────────────────────────
SUB_ASSEMBLY_NAME = 'Motorized Lift Frame'

sub_templates = execute('product.template', 'search_read',
    [[['name', 'ilike', SUB_ASSEMBLY_NAME]]],
    {'fields': ['id', 'name'], 'order': 'id desc', 'limit': 1})

sub_assembly_tmpl_id = None
sub_assembly_prod_id = None

if sub_templates:
    sub_assembly_tmpl_id = sub_templates[0]['id']

    # Get product.product ID
    sub_variants = execute('product.product', 'search_read',
        [[['product_tmpl_id', '=', sub_assembly_tmpl_id]]],
        {'fields': ['id'], 'limit': 1})
    sub_assembly_prod_id = sub_variants[0]['id'] if sub_variants else None

    # Find BOM for sub-assembly
    sub_boms = execute('mrp.bom', 'search_read',
        [[['product_tmpl_id', '=', sub_assembly_tmpl_id]]],
        {'fields': ['id', 'bom_line_ids']})

    sub_bom_lines = []
    if sub_boms:
        lines = execute('mrp.bom.line', 'read',
            sub_boms[0]['bom_line_ids'],
            ['product_id', 'product_qty'])
        for line in lines:
            sub_bom_lines.append({
                'product_name': line['product_id'][1] if isinstance(line['product_id'], list) else '',
                'product_id': line['product_id'][0] if isinstance(line['product_id'], list) else line['product_id'],
                'qty': line['product_qty'],
            })

    result['sub_assembly_bom'] = {
        'found': len(sub_boms) > 0,
        'product_found': True,
        'tmpl_id': sub_assembly_tmpl_id,
        'prod_id': sub_assembly_prod_id,
        'lines': sub_bom_lines,
    }
    print(f"Sub-assembly BOM: {len(sub_bom_lines)} lines")
else:
    result['sub_assembly_bom'] = {'found': False, 'product_found': False}
    print("Sub-assembly 'Motorized Lift Frame' NOT found.")

# ─── 3. Main BOM: SmartDesk Pro ──────────────────────────────────────────────
if template_id:
    main_boms = execute('mrp.bom', 'search_read',
        [[['product_tmpl_id', '=', template_id]]],
        {'fields': ['id', 'bom_line_ids']})

    main_bom_lines = []
    if main_boms:
        lines = execute('mrp.bom.line', 'read',
            main_boms[0]['bom_line_ids'],
            ['product_id', 'product_qty', 'bom_product_template_attribute_value_ids'])
        for line in lines:
            main_bom_lines.append({
                'product_name': line['product_id'][1] if isinstance(line['product_id'], list) else '',
                'product_id': line['product_id'][0] if isinstance(line['product_id'], list) else line['product_id'],
                'qty': line['product_qty'],
                'variant_restriction_ids': line['bom_product_template_attribute_value_ids'],
            })

    result['main_bom'] = {
        'found': len(main_boms) > 0,
        'lines': main_bom_lines,
    }
    print(f"Main BOM: {len(main_bom_lines)} lines")
else:
    result['main_bom'] = {'found': False, 'lines': []}

# ─── 4. Pricelist: Authorized Dealer Network ─────────────────────────────────
PRICELIST_NAME = 'Authorized Dealer Network'

pricelists = execute('product.pricelist', 'search_read',
    [[['name', 'ilike', PRICELIST_NAME]]],
    {'fields': ['id', 'name']})

pricelist_id = None
pricelist_items = []

if pricelists:
    pricelist_id = pricelists[0]['id']

    items = execute('product.pricelist.item', 'search_read',
        [[['pricelist_id', '=', pricelist_id]]],
        {'fields': ['product_tmpl_id', 'min_quantity', 'fixed_price',
                    'compute_price', 'percent_price', 'price_discount',
                    'applied_on']})
    for item in items:
        pricelist_items.append({
            'product': item['product_tmpl_id'][1] if item['product_tmpl_id'] else None,
            'min_qty': item['min_quantity'],
            'fixed_price': item['fixed_price'],
            'compute_price': item['compute_price'],
            'percent_price': item.get('percent_price', 0),
            'price_discount': item.get('price_discount', 0),
            'applied_on': item['applied_on'],
        })

    result['pricelist'] = {
        'found': True,
        'id': pricelist_id,
        'name': pricelists[0]['name'],
        'items': pricelist_items,
    }
    print(f"Pricelist found: {pricelists[0]['name']} with {len(pricelist_items)} items")
else:
    result['pricelist'] = {'found': False}
    print("Pricelist 'Authorized Dealer Network' NOT found.")

# ─── 5. Manufacturing Order (validation MO) ──────────────────────────────────
# Find MO for a SmartDesk Pro variant (any)
if template_id:
    # Get all variant IDs for this template
    all_variants = execute('product.product', 'search_read',
        [[['product_tmpl_id', '=', template_id]]],
        {'fields': ['id', 'product_template_attribute_value_ids']})

    variant_ids = [v['id'] for v in all_variants]

    if variant_ids:
        mos = execute('mrp.production', 'search_read',
            [[['product_id', 'in', variant_ids]]],
            {'fields': ['id', 'name', 'state', 'product_id', 'product_qty', 'move_raw_ids'],
             'order': 'id desc', 'limit': 1})

        if mos:
            mo = mos[0]
            mo_components = []
            if mo.get('move_raw_ids'):
                moves = execute('stock.move', 'read',
                    mo['move_raw_ids'],
                    ['product_id', 'product_uom_qty', 'quantity', 'state'])
                for m in moves:
                    mo_components.append({
                        'product_name': m['product_id'][1] if isinstance(m['product_id'], list) else '',
                        'product_id': m['product_id'][0] if isinstance(m['product_id'], list) else m['product_id'],
                        'qty_demanded': m['product_uom_qty'],
                        'qty_done': m.get('quantity', 0),
                        'state': m['state'],
                    })

            result['manufacturing_order'] = {
                'found': True,
                'id': mo['id'],
                'name': mo['name'],
                'state': mo['state'],
                'product_id': mo['product_id'][0] if isinstance(mo['product_id'], list) else mo['product_id'],
                'product_name': mo['product_id'][1] if isinstance(mo['product_id'], list) else '',
                'product_qty': mo['product_qty'],
                'components': mo_components,
            }
            print(f"Found MO: {mo['name']} state={mo['state']}")
        else:
            result['manufacturing_order'] = {'found': False}
            print("No manufacturing order found.")
    else:
        result['manufacturing_order'] = {'found': False}
else:
    result['manufacturing_order'] = {'found': False}

# ─── 6. Sales Order for Cascade Furniture Partners ────────────────────────────
if customer_id and template_id:
    orders = execute('sale.order', 'search_read',
        [[['partner_id', '=', customer_id]]],
        {'fields': ['id', 'name', 'state', 'amount_total', 'amount_untaxed',
                    'pricelist_id'],
         'order': 'id desc'})

    target_so = None
    so_lines = []

    for order in orders:
        lines = execute('sale.order.line', 'search_read',
            [[['order_id', '=', order['id']]]],
            {'fields': ['product_id', 'product_uom_qty', 'price_unit',
                        'price_subtotal']})
        # Check if this order has a SmartDesk Pro variant
        for line in lines:
            pid = line['product_id'][0] if isinstance(line.get('product_id'), list) else line.get('product_id')
            if pid in variant_ids:
                target_so = order
                so_lines = lines
                break
        if target_so:
            break

    if target_so:
        result['sales_order'] = {
            'found': True,
            'id': target_so['id'],
            'name': target_so['name'],
            'state': target_so['state'],
            'amount_total': target_so['amount_total'],
            'amount_untaxed': target_so['amount_untaxed'],
            'pricelist_id': target_so['pricelist_id'][0] if isinstance(target_so.get('pricelist_id'), list) else None,
            'pricelist_name': target_so['pricelist_id'][1] if isinstance(target_so.get('pricelist_id'), list) else None,
            'lines': [{
                'product_name': l['product_id'][1] if isinstance(l.get('product_id'), list) else '',
                'qty': l['product_uom_qty'],
                'price_unit': l['price_unit'],
                'price_subtotal': l['price_subtotal'],
            } for l in so_lines],
        }
        print(f"Found SO: {target_so['name']} state={target_so['state']} total={target_so['amount_untaxed']}")
    else:
        result['sales_order'] = {'found': False}
        print("No sales order found for Cascade Furniture Partners.")
else:
    result['sales_order'] = {'found': False}

# ─── Write Result ─────────────────────────────────────────────────────────────
with open('/tmp/smartdesk_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

print("\nExport successful.")
PYEOF

# Copy to canonical location
cp /tmp/smartdesk_result.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
