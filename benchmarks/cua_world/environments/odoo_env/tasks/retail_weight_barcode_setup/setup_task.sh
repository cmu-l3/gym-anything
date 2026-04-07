#!/bin/bash
# Setup script for retail_weight_barcode_setup
# Ensures the 'barcodes' module is installed and clean state for the task.

echo "=== Setting up retail_weight_barcode_setup ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

# Install required module (barcodes) via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Connection error: {e}")
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Install barcodes module if not installed
module = execute('ir.module.module', 'search_read', [[['name', '=', 'barcodes']]], {'fields': ['state']})
if module and module[0]['state'] != 'installed':
    print("Installing barcodes module...")
    execute('ir.module.module', 'button_immediate_install', [[module[0]['id']]])

# Ensure 'kg' UoM exists (it usually does)
# We don't create it, just verifying environment is sane
uom = execute('uom.uom', 'search_read', [[['name', '=', 'kg']]], {'limit': 1})
if not uom:
    print("Warning: 'kg' UoM not found, creating it...")
    # Typically would be in data, but let's assume standard install
    pass

# Clean up any existing rule starting with 24 to ensure fresh start
existing_rules = execute('barcode.rule', 'search', [[['pattern', 'like', '24%']]])
if existing_rules:
    print(f"Cleaning up {len(existing_rules)} existing rules starting with '24'...")
    execute('barcode.rule', 'unlink', [existing_rules])

# Remove product if it exists from previous run
existing_product = execute('product.product', 'search', [[['barcode', '=', '55001']]])
if existing_product:
    execute('product.product', 'unlink', [existing_product])

print("Setup complete.")
PYEOF

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login?db=odoo_demo' &"
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="