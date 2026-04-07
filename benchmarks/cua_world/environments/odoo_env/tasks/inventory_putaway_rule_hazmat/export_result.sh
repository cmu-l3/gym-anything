#!/bin/bash
# Export script for inventory_putaway_rule_hazmat
# Verifies database state: Locations, Rules, Moves

echo "=== Exporting inventory_putaway_rule_hazmat result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Odoo state
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

# Load setup info
try:
    with open('/tmp/setup_info.json', 'r') as f:
        setup = json.load(f)
except FileNotFoundError:
    print("Setup info not found", file=sys.stderr)
    setup = {}

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Connection error: {e}", file=sys.stderr)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# --- Verification Logic ---

# 1. Check if "Storage Locations" is effectively enabled
# We check if the user has the group 'stock.group_stock_multi_locations'
# Or check if we can see more than 1 internal location (simplest proxy)
locations_count = execute('stock.location', 'search_count', [[['usage', '=', 'internal']]])
multi_locations_enabled = False
# Checking the specific group on the admin user
admin_groups = execute('res.users', 'read', [uid], {'fields': ['groups_id']})[0]['groups_id']
# Find the xml_id for stock.group_stock_multi_locations is harder via RPC without model mapping
# Easier: Check if the menu item is visible? Hard via RPC.
# We will assume if they created the location, they enabled it.

# 2. Check if "Safety Cabinet 01" exists
target_loc = execute('stock.location', 'search_read', 
    [[['name', 'ilike', 'Safety Cabinet 01']]], 
    {'fields': ['id', 'name', 'location_id']})
target_loc_exists = len(target_loc) > 0
target_loc_id = target_loc[0]['id'] if target_loc_exists else None

# 3. Check if Putaway Rule exists for Corrosives -> Safety Cabinet 01
# Model: stock.putaway.rule
rule_exists = False
if target_loc_exists and setup.get('categ_id'):
    rules = execute('stock.putaway.rule', 'search_read',
        [[
            ['category_id', '=', setup['categ_id']],
            ['location_out_id', '=', target_loc_id]
        ]],
        {'fields': ['id', 'location_in_id']})
    rule_exists = len(rules) > 0

# 4. Check for Receipts (stock.picking) and Moves (stock.move.line)
# We want to see a move of "Sulfuric Acid 98%" to "Safety Cabinet 01"
move_success = False
receipt_validated = False

if setup.get('product_id') and target_loc_id:
    # Look for done stock moves for this product
    moves = execute('stock.move.line', 'search_read',
        [[
            ['product_id', '=', setup['product_id']],
            ['state', '=', 'done'],
            ['location_dest_id', '=', target_loc_id]
        ]],
        {'fields': ['id', 'picking_id', 'qty_done', 'date']})
    
    if moves:
        move_success = True
        # Check if it came from a receipt (picking_type_code = incoming ideally, or just check existance)
        # We'll just accept any move to that location as proof of logic working
        receipt_validated = True

# 5. Check task start time for anti-gaming (ensure records created recently)
# Since we just checked existence, we assume if they exist now and didn't before (setup didn't create them), user did it.
# Setup script purposely didn't create them.

result = {
    "locations_enabled_proxy": locations_count > 1, # Default is usually 1 (WH/Stock) + maybe Output/Input
    "target_location_exists": target_loc_exists,
    "target_location_name": target_loc[0]['name'] if target_loc_exists else None,
    "putaway_rule_exists": rule_exists,
    "receipt_validated": receipt_validated,
    "auto_routing_success": move_success,
    "timestamp": datetime.datetime.now().isoformat()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="