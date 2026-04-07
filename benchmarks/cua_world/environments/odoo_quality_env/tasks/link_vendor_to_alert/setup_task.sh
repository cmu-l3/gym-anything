#!/bin/bash
set -e
echo "=== Setting up link_vendor_to_alert task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Run Python script to setup data in Odoo
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time
import json

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

def connect():
    common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
    uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")
    return uid, models

try:
    uid, models = connect()
    
    # 1. Ensure Vendor "Wood Corner" exists
    vendor_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'res.partner', 'search', 
        [[['name', '=', 'Wood Corner']]])
    
    if not vendor_ids:
        vendor_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'res.partner', 'create', [{
            'name': 'Wood Corner',
            'company_type': 'company',
            'supplier_rank': 1
        }])
        print(f"Created vendor 'Wood Corner' (id={vendor_id})")
    else:
        vendor_id = vendor_ids[0]
        print(f"Found vendor 'Wood Corner' (id={vendor_id})")

    # 2. Get Product "Cabinet with Doors"
    product_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'product.product', 'search',
        [[['name', 'ilike', 'Cabinet with Doors']]])
    
    if not product_ids:
        # Fallback if specific product missing (unlikely in this env)
        product_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'product.product', 'search', [])
    product_id = product_ids[0]
    
    # 3. Clean up any existing alert with the target name to ensure fresh state
    target_name = "Surface Defects on Cabinet Batch"
    existing_alerts = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.alert', 'search',
        [[['name', '=', target_name]]])
    
    if existing_alerts:
        models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.alert', 'unlink', [existing_alerts])
        print(f"Removed {len(existing_alerts)} existing alerts named '{target_name}'")

    # 4. Create the target Quality Alert (without vendor)
    alert_vals = {
        'name': target_name,
        'product_id': product_id,
        'description': 'Inspection found scratches on front panels.',
        'partner_id': False  # Explicitly empty
    }
    alert_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.alert', 'create', [alert_vals])
    print(f"Created target alert (id={alert_id})")

    # Save setup info for verification
    setup_info = {
        "alert_id": alert_id,
        "vendor_id": vendor_id,
        "product_id": product_id,
        "setup_time": time.time()
    }
    with open('/tmp/setup_info.json', 'w') as f:
        json.dump(setup_info, f)

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Ensure Firefox is open and on the alerts page
ensure_firefox "http://localhost:8069/web#action=quality.quality_alert_action_team"

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="