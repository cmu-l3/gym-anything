#!/bin/bash
# Setup script for fleet_lease_service_lifecycle task
# Installs Fleet module, creates necessary metadata (Model, Vendor), and ensures clean state.

echo "=== Setting up fleet_lease_service_lifecycle ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp

# Wait for Odoo to be ready
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null; then
        break
    fi
    sleep 3
done
sleep 2

# Execute Python setup script via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

def get_connection():
    try:
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USERNAME, PASSWORD, {})
        if not uid:
            return None, None
        models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
        return uid, models
    except Exception as e:
        print(f"Connection error: {e}")
        return None, None

uid, models = get_connection()
if not uid:
    print("ERROR: Could not connect to Odoo")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# 1. Install Fleet module if not installed
print("Checking Fleet module installation...")
module = execute('ir.module.module', 'search_read', [[['name', '=', 'fleet']]], {'fields': ['state', 'id']})
if module and module[0]['state'] != 'installed':
    print("Installing Fleet module (this may take a moment)...")
    execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])
    # Re-authenticate after installation restart
    time.sleep(5)
    uid, models = get_connection()

# 2. Create/Find Vendor "Gemini Fleet Services"
print("Setting up Vendor...")
vendor = execute('res.partner', 'search_read', [[['name', '=', 'Gemini Fleet Services']]], {'limit': 1})
if not vendor:
    vendor_id = execute('res.partner', 'create', [{'name': 'Gemini Fleet Services', 'is_company': True, 'supplier_rank': 1}])
    print(f"Created Vendor: Gemini Fleet Services (id={vendor_id})")
else:
    print("Vendor Gemini Fleet Services already exists")

# 3. Create/Find Brand "Ford" and Model "Transit"
print("Setting up Vehicle Model...")
brand = execute('fleet.vehicle.model.brand', 'search_read', [[['name', '=', 'Ford']]], {'limit': 1})
if not brand:
    brand_id = execute('fleet.vehicle.model.brand', 'create', [{'name': 'Ford'}])
else:
    brand_id = brand[0]['id']

model = execute('fleet.vehicle.model', 'search_read', [[['name', '=', 'Transit'], ['brand_id', '=', brand_id]]], {'limit': 1})
if not model:
    model_id = execute('fleet.vehicle.model', 'create', [{'name': 'Transit', 'brand_id': brand_id, 'vehicle_type': 'car'}])
    print(f"Created Model: Ford Transit (id={model_id})")
else:
    print("Model Ford Transit already exists")

# 4. Clean up target vehicle if it already exists (to prevent collisions)
print("Cleaning up existing target vehicle...")
target_plate = "TRK-885-XJ"
existing_vehicle = execute('fleet.vehicle', 'search', [[['license_plate', '=', target_plate]]])
if existing_vehicle:
    execute('fleet.vehicle', 'unlink', [existing_vehicle])
    print(f"Removed existing vehicle with plate {target_plate}")

print("Setup complete.")
PYEOF

# Ensure application window is ready
# (Using shared utility if available, otherwise manual check)
if type wait_for_window &>/dev/null; then
    wait_for_window "Odoo" 10 || true
fi

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="