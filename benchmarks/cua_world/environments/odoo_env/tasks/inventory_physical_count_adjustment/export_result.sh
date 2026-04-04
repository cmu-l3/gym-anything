#!/bin/bash
# Export script for inventory_physical_count_adjustment task
# Queries current stock quantities and reorder rules for the 3 setup products.

echo "=== Exporting inventory_physical_count_adjustment Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

if [ ! -f /tmp/inventory_physical_count_setup.json ]; then
    echo "ERROR: Setup data not found"
    echo '{"error": "setup_data_missing"}' > /tmp/inventory_physical_count_adjustment_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

with open('/tmp/inventory_physical_count_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/inventory_physical_count_adjustment_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

task_start = 0
try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

location_id = setup['location_id']
products_result = []

for prod in setup['products']:
    product_id = prod['product_id']
    expected_physical_qty = prod['physical_qty']
    system_qty = prod['system_qty']

    # Get current on-hand quantity
    quants = execute('stock.quant', 'search_read',
        [[['product_id', '=', product_id], ['location_id', '=', location_id]]],
        {'fields': ['id', 'quantity', 'inventory_quantity', 'inventory_date']})

    current_qty = sum(q.get('quantity', 0) for q in quants) if quants else system_qty

    # Check if adjusted to expected physical count
    qty_correct = abs(current_qty - expected_physical_qty) < 0.5
    qty_changed = abs(current_qty - system_qty) > 0.5

    # Check for reorder rules (stock.warehouse.orderpoint)
    reorder_rules = execute('stock.warehouse.orderpoint', 'search_read',
        [[['product_id', '=', product_id]]],
        {'fields': ['id', 'product_min_qty', 'product_max_qty', 'product_id',
                    'location_id', 'active']})

    has_reorder_rule = len(reorder_rules) > 0
    reorder_min_correct = False
    reorder_max_correct = False
    if reorder_rules:
        rule = reorder_rules[0]
        reorder_min_correct = abs(float(rule.get('product_min_qty', 0)) - 15) < 0.5
        reorder_max_correct = abs(float(rule.get('product_max_qty', 0)) - 60) < 0.5

    products_result.append({
        'product_id': product_id,
        'name': prod['name'],
        'original_system_qty': system_qty,
        'expected_physical_qty': expected_physical_qty,
        'current_qty': current_qty,
        'qty_correct': qty_correct,
        'qty_changed': qty_changed,
        'has_reorder_rule': has_reorder_rule,
        'reorder_min_correct': reorder_min_correct,
        'reorder_max_correct': reorder_max_correct,
        'reorder_rules_count': len(reorder_rules),
    })

    print(f"Product: {prod['name']}")
    print(f"  System: {system_qty} | Physical: {expected_physical_qty} | Current: {current_qty} | Correct: {qty_correct}")
    print(f"  Reorder rule: {has_reorder_rule} | Min correct: {reorder_min_correct} | Max correct: {reorder_max_correct}")

# Summary counts
products_adjusted_correctly = sum(1 for p in products_result if p['qty_correct'])
products_with_reorder_rules = sum(1 for p in products_result if p['has_reorder_rule'])
products_with_correct_min = sum(1 for p in products_result if p['reorder_min_correct'])
products_with_correct_max = sum(1 for p in products_result if p['reorder_max_correct'])
products_with_full_correct_reorder = sum(
    1 for p in products_result if p['reorder_min_correct'] and p['reorder_max_correct']
)

result = {
    'task': 'inventory_physical_count_adjustment',
    'task_start': task_start,
    'products': products_result,
    'location_id': location_id,
    'location_name': setup['location_name'],
    'products_adjusted_correctly': products_adjusted_correctly,
    'products_with_reorder_rules': products_with_reorder_rules,
    'products_with_correct_min': products_with_correct_min,
    'products_with_correct_max': products_with_correct_max,
    'products_with_full_correct_reorder': products_with_full_correct_reorder,
    'total_products': len(setup['products']),
    'export_timestamp': __import__('datetime').datetime.now().isoformat(),
}

with open('/tmp/inventory_physical_count_adjustment_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"\nSummary: {products_adjusted_correctly}/3 adjusted correctly, "
      f"{products_with_full_correct_reorder}/3 have correct reorder rules")
PYEOF

echo "=== Export Complete ==="
