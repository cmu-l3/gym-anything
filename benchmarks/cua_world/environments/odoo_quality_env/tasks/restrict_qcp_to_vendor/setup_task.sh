#!/bin/bash
echo "=== Setting up restrict_qcp_to_vendor task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create specific data for this task using Python/XML-RPC
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import time

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

def connect():
    for i in range(5):
        try:
            common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
            uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
            models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")
            return uid, models
        except Exception as e:
            print(f"Connection attempt {i+1} failed: {e}")
            time.sleep(2)
    sys.exit(1)

uid, models = connect()

# 1. Get/Create Partner "Gemini Furniture"
partner_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'res.partner', 'search', [[['name', '=', 'Gemini Furniture']]])
if partner_ids:
    partner_id = partner_ids[0]
    print(f"Found existing partner: Gemini Furniture ({partner_id})")
else:
    partner_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'res.partner', 'create', [{'name': 'Gemini Furniture', 'supplier_rank': 1}])
    print(f"Created partner: Gemini Furniture ({partner_id})")

# 2. Get Product "Cabinet with Doors"
# Odoo 17 uses JSONB for names sometimes, but ilike usually works for search
product_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'product.product', 'search', [[['name', 'ilike', 'Cabinet with Doors']]])
if not product_ids:
    # Fallback: create if missing
    tmpl_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'product.template', 'create', [{'name': 'Cabinet with Doors', 'type': 'product'}])
    product_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'product.product', 'search', [[['product_tmpl_id', '=', tmpl_id]]])
product_id = product_ids[0]
print(f"Using product id: {product_id}")

# 3. Get Receipts Operation Type
picking_type_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'stock.picking.type', 'search', [[['code', '=', 'incoming']]])
picking_type_id = picking_type_ids[0] if picking_type_ids else False
print(f"Using picking type id: {picking_type_id}")

# 4. Create the QCP (Reset if exists to ensure vendor is empty)
# Delete existing QCP with this title to ensure clean state
old_qcp_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.point', 'search', [[['title', '=', 'Cabinet Inspection']]])
if old_qcp_ids:
    models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.point', 'unlink', [old_qcp_ids])
    print("Deleted stale QCP record")

# Determine a test type (prefer 'passfail')
test_type_id = False
try:
    # Try finding the ID for 'Pass - Fail'
    type_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.check.type', 'search', [[['name', 'ilike', 'Pass']]])
    if type_ids:
        test_type_id = type_ids[0]
except Exception:
    pass

qcp_vals = {
    'title': 'Cabinet Inspection',
    'product_ids': [[6, 0, [product_id]]],
    'picking_type_ids': [[6, 0, [picking_type_id]]] if picking_type_id else [],
    'partner_id': False, # Explicitly empty - this is the task goal!
    'note': 'Inspect for surface scratches on doors.',
}

# Handle Odoo version differences for test_type
if test_type_id:
    qcp_vals['test_type_id'] = test_type_id
else:
    qcp_vals['test_type'] = 'passfail'

try:
    qcp_id = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.point', 'create', [qcp_vals])
    print(f"Created QCP 'Cabinet Inspection' (id={qcp_id}) with empty partner_id")
except Exception as e:
    print(f"Error creating QCP: {e}")
    sys.exit(1)

PYTHON_EOF

# Launch Firefox and navigate to the Quality Control Points list
ensure_firefox "http://localhost:8069/web#action=quality_control.quality_point_action&view_type=list"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="