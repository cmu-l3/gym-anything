#!/bin/bash
# Setup script for equipment_maintenance_management task
# 1. Installs 'maintenance' module if not present
# 2. Creates existing equipment "Hydraulic Press"
# 3. Records initial state and timestamps

echo "=== Setting up equipment_maintenance_management ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 60); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 2
done
sleep 2

# Run Python setup via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# ─── 1. Ensure Maintenance Module is Installed ───────────────────────────────
# Check if installed
module_search = execute('ir.module.module', 'search_read',
    [[['name', '=', 'maintenance'], ['state', '=', 'installed']]],
    {'fields': ['id', 'state']})

if not module_search:
    print("Maintenance module not installed. Installing... (this may take a minute)")
    # Find the module
    module_id = execute('ir.module.module', 'search', [[['name', '=', 'maintenance']]])
    if module_id:
        # Install immediate
        execute('ir.module.module', 'button_immediate_install', [module_id])
        # Wait a bit for installation to finalize in DB
        time.sleep(10)
    else:
        print("ERROR: Maintenance module not found in system!", file=sys.stderr)
        sys.exit(1)
else:
    print("Maintenance module is already installed.")

# ─── 2. Setup Existing Equipment (Hydraulic Press) ───────────────────────────
TARGET_EQUIP = "Hydraulic Press - Schuler 2500T"

existing_equip = execute('maintenance.equipment', 'search_read',
    [[['name', '=', TARGET_EQUIP]]],
    {'fields': ['id', 'name']})

if existing_equip:
    equip_id = existing_equip[0]['id']
    print(f"Using existing equipment: {TARGET_EQUIP} (id={equip_id})")
else:
    # Need a category first usually, or use default
    # Let's check for 'Heavy Machinery' category or create it
    cat_ids = execute('maintenance.equipment.category', 'search', [[['name', '=', 'Heavy Machinery']]])
    if cat_ids:
        cat_id = cat_ids[0]
    else:
        cat_id = execute('maintenance.equipment.category', 'create', [{'name': 'Heavy Machinery'}])

    equip_id = execute('maintenance.equipment', 'create', [{
        'name': TARGET_EQUIP,
        'category_id': cat_id,
        'effective_date': '2023-01-01',
        'cost': 125000.00,
    }])
    print(f"Created equipment: {TARGET_EQUIP} (id={equip_id})")

# ─── 3. Ensure a Maintenance Team Exists ─────────────────────────────────────
team_ids = execute('maintenance.team', 'search', [])
if not team_ids:
    team_id = execute('maintenance.team', 'create', [{'name': 'Internal Maintenance'}])
    print(f"Created maintenance team (id={team_id})")
else:
    print(f"Found {len(team_ids)} maintenance teams.")

# ─── 4. Record Initial Counts ────────────────────────────────────────────────
equip_count = execute('maintenance.equipment', 'search_count', [[]])
req_count = execute('maintenance.request', 'search_count', [[]])

setup_data = {
    'target_equip_id': equip_id,
    'target_equip_name': TARGET_EQUIP,
    'initial_equip_count': equip_count,
    'initial_request_count': req_count,
    'setup_timestamp': time.time()
}

with open('/tmp/equipment_maintenance_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print("Setup complete.")
PYEOF

# Ensure Firefox is open to the main page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="