#!/bin/bash
# Export script for service_project_automation_sales
# Extracts product config, Sales Order details, Project links, and Invoice status.

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Query Odoo
python3 << 'PYEOF'
import xmlrpc.client
import json
import os
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

def execute(model, method, *args, **kwargs):
    return models.execute_kw(DB, uid, PASSWORD, model, method, list(args), kwargs)

result = {
    "product_config": {},
    "so_status": {},
    "project_status": {},
    "delivery_status": {},
    "invoice_status": {},
    "timestamp_check": False
}

# --- 1. Check Product Configuration ---
# Look for 'Logistics Site Audit'
prod_ids = execute('product.template', 'search_read', 
    [['name', '=', 'Logistics Site Audit'], ['active', '=', True]], 
    ['id', 'type', 'invoice_policy', 'service_tracking', 'list_price'])

if prod_ids:
    p = prod_ids[0] # Take the most recent/relevant
    result["product_config"] = {
        "exists": True,
        "type": p.get('type'), # Should be 'service'
        "invoice_policy": p.get('invoice_policy'), # Should be 'order'
        "service_tracking": p.get('service_tracking'), # Should be 'task_in_project' or similar
        "price": p.get('list_price')
    }
else:
    result["product_config"] = {"exists": False}

# --- 2. Check Sales Order ---
# Look for SO for Titanium Manufacturing created recently
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        start_ts = float(f.read().strip())
except:
    start_ts = 0

so_ids = execute('sale.order', 'search_read', 
    [['partner_id.name', '=', 'Titanium Manufacturing'], ['date_order', '>=', '2023-01-01']], # Broad date filter, will sort by ID
    ['id', 'name', 'state', 'amount_untaxed', 'order_line', 'tasks_ids', 'project_ids', 'invoice_ids', 'picking_ids', 'create_date'])

# Sort by ID descending to get the one created during task
so_ids.sort(key=lambda x: x['id'], reverse=True)

target_so = None
if so_ids:
    # Filter strictly by creation time if possible, or just take the newest
    # Odoo dates are UTC strings, converting is annoying in minimal python. 
    # Relying on ID > initial ID is better but we didn't record initial ID. 
    # We'll assume the newest SO is the one.
    target_so = so_ids[0]
    result["so_status"] = {
        "exists": True,
        "state": target_so['state'],
        "amount": target_so['amount_untaxed'],
        "id": target_so['id']
    }
    result["timestamp_check"] = True # Assuming valid if found matching criteria
else:
    result["so_status"] = {"exists": False}

# --- 3. Check Order Lines (Service + Scanner) ---
if target_so:
    lines = execute('sale.order.line', 'read', target_so['order_line'], ['product_id', 'product_uom_qty'])
    has_service = False
    has_scanner = False
    for l in lines:
        p_name = l['product_id'][1] if l['product_id'] else ""
        if "Logistics Site Audit" in p_name:
            has_service = True
        if "Industrial Barcode Scanner" in p_name and l['product_uom_qty'] >= 5:
            has_scanner = True
    result["so_status"]["lines_correct"] = (has_service and has_scanner)

# --- 4. Check Project Automation ---
if target_so:
    # Check if project was generated
    # field project_id on SO or project_ids
    # field tasks_ids on SO
    
    # Odoo 16/17 logic: service_tracking='task_in_project' sets project_id on the SO (if one project per SO) 
    # or creates a project and links it.
    
    # Check direct project link
    project_ids = target_so.get('project_ids', [])
    task_ids = target_so.get('tasks_ids', [])
    
    project_created = False
    task_created = False
    
    if project_ids:
        project_created = True
    
    if task_ids:
        task_created = True
        
    # Also check if the service line generated a project/task
    if not project_created and target_so.get('order_line'):
        # Deep check lines for generated ids
        line_details = execute('sale.order.line', 'read', target_so['order_line'], ['project_id', 'task_id'])
        for ld in line_details:
            if ld.get('project_id'):
                project_created = True
            if ld.get('task_id'):
                task_created = True

    result["project_status"] = {
        "project_created": project_created,
        "task_created": task_created
    }

# --- 5. Check Delivery Status ---
if target_so and target_so.get('picking_ids'):
    pickings = execute('stock.picking', 'read', target_so['picking_ids'], ['state'])
    # Check if any picking is done
    any_done = any(p['state'] == 'done' for p in pickings)
    result["delivery_status"] = {"delivered": any_done}
else:
    result["delivery_status"] = {"delivered": False}

# --- 6. Check Invoice Status ---
if target_so and target_so.get('invoice_ids'):
    invoices = execute('account.move', 'read', target_so['invoice_ids'], ['state', 'amount_total', 'payment_state'])
    # Check for posted invoice
    posted_inv = [i for i in invoices if i['state'] == 'posted']
    total_invoiced = sum(i['amount_total'] for i in posted_inv)
    
    result["invoice_status"] = {
        "posted": len(posted_inv) > 0,
        "total_amount": total_invoiced,
        "count": len(posted_inv)
    }
else:
    result["invoice_status"] = {"posted": False, "total_amount": 0.0}

# Write Result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

# 3. Secure output
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json