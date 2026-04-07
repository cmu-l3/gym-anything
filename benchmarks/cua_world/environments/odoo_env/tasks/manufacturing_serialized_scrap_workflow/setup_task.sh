#!/bin/bash
# Setup script for manufacturing_serialized_scrap_workflow
# Creates a Manufacturing Order with specific serialized components available in stock.

echo "=== Setting up Manufacturing Serialized Scrap Workflow ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in {1..30}; do
    if curl -s "http://localhost:8069/web/webclient/version_info" > /dev/null; then
        break
    fi
    sleep 2
done

# 2. Run Python setup via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Error connecting to Odoo: {e}")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Install MRP module if not installed
module = execute('ir.module.module', 'search_read', [[['name', '=', 'mrp']]], {'fields': ['state']})
if not module or module[0]['state'] != 'installed':
    print("Installing Manufacturing module...")
    execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])
    time.sleep(10)

# Create Component Product (Tracking: Serial)
component_id = execute('product.product', 'create', [{
    'name': 'Optical Lens Array',
    'type': 'product',
    'tracking': 'serial',
    'standard_price': 150.0,
}])

# Create Final Product (Tracking: Serial)
final_product_id = execute('product.product', 'create', [{
    'name': '4K Laser Projector',
    'type': 'product',
    'tracking': 'serial',
    'list_price': 2500.0,
}])

# Create BOM
bom_id = execute('mrp.bom', 'create', [{
    'product_tmpl_id': execute('product.product', 'read', [final_product_id], ['product_tmpl_id'])[0]['product_tmpl_id'][0],
    'product_qty': 1.0,
    'bom_line_ids': [
        (0, 0, {
            'product_id': component_id,
            'product_qty': 1.0,
        })
    ]
}])

# Create Serial Numbers (Lots) for Component
stock_location = execute('stock.location', 'search', [[['usage', '=', 'internal']]], {'limit': 1})[0]

lens_sns = ['LENS-A001', 'LENS-A002', 'LENS-A003']
lens_lot_ids = {}

for sn in lens_sns:
    lot_id = execute('stock.lot', 'create', [{
        'name': sn,
        'product_id': component_id,
        'company_id': 1,
    }])
    lens_lot_ids[sn] = lot_id
    
    # Add stock via inventory adjustment (stock.quant)
    execute('stock.quant', 'create', [{
        'product_id': component_id,
        'location_id': stock_location,
        'lot_id': lot_id,
        'quantity': 1.0,
    }])

print("Created component serials: LENS-A001, LENS-A002, LENS-A003")

# Create Manufacturing Order
mo_id = execute('mrp.production', 'create', [{
    'product_id': final_product_id,
    'product_qty': 1.0,
    'product_uom_id': 1,
    'bom_id': bom_id,
    'name': 'MO-00001',  # Force specific name if possible, or let sequence handle it
}])

# Confirm the MO
execute('mrp.production', 'action_confirm', [[mo_id]])

# Force renaming to MO-00001 to ensure instructions match
execute('mrp.production', 'write', [[mo_id], {'name': 'MO-00001'}])

print(f"Created MO-00001 (id={mo_id})")

# By default, Odoo might reserve LENS-A001 (based on FIFO/Name). 
# We want to ensure LENS-A001 is the one 'assigned' so the agent has to scrap IT.
# We check the moves.
move_raw_ids = execute('mrp.production', 'read', [mo_id], ['move_raw_ids'])[0]['move_raw_ids']
# Force reservation of LENS-A001 if not already done, or ensure setup guides agent to it.
# Simpler approach: The prompt says "LENS-A001 was damaged". Agent just needs to find it.

PYEOF

# 3. Create Damage Report on Desktop
cat > /home/ga/Desktop/damage_report.txt << EOF
INCIDENT REPORT #8842
DATE: $(date +%F)
TECHNICIAN: J. Doe

ITEM: Optical Lens Array
SN: LENS-A001
ISSUE: Deep scratch on anterior element during mounting attempt.

ACTION REQUIRED:
1. Scrap LENS-A001 from MO-00001.
2. Use LENS-A002 as replacement.
3. Finish assembly of Projector (SN: PROJ-X99).
EOF

chmod 644 /home/ga/Desktop/damage_report.txt

# 4. Launch Firefox
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo&login=admin&password=admin' &"

# 5. Wait for Firefox and maximize
sleep 10
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# 7. Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="