#!/bin/bash
# Export script for analytic_cost_allocation task
# Queries Odoo to verify analytic configuration and bill allocation

echo "=== Exporting analytic_cost_allocation Result ==="

# Record task end time and get start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to query Odoo via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# --- Verify Analytic Plan ---
plan_name = "Department Costs"
plans = execute('account.analytic.plan', 'search_read',
    [[['name', '=', plan_name]]],
    {'fields': ['id', 'name']})
plan_found = bool(plans)
plan_id = plans[0]['id'] if plans else None

# --- Verify Analytic Accounts ---
target_accounts = ["Engineering Dept", "Marketing Dept", "Operations Dept"]
found_accounts = {}
account_id_to_name = {}

if plan_id:
    # Find accounts linked to this plan
    accounts = execute('account.analytic.account', 'search_read',
        [[['plan_id', '=', plan_id]]],
        {'fields': ['id', 'name']})
    
    for acc in accounts:
        name = acc['name']
        if name in target_accounts:
            found_accounts[name] = True
            account_id_to_name[str(acc['id'])] = name

# --- Verify Vendor Bill ---
vendor_name = "Deco Addict"
# Search for posted bills for this vendor created recently
# Note: filtering by create_date is complex via RPC depending on server timezone, 
# so we fetch recent ones and check IDs or simple properties.
bills = execute('account.move', 'search_read',
    [[['move_type', '=', 'in_invoice'], 
      ['partner_id.name', '=', vendor_name],
      ['state', '=', 'posted']]],
    {'fields': ['id', 'name', 'amount_total', 'invoice_line_ids'], 'order': 'id desc', 'limit': 1})

bill_found = False
bill_correct_amount = False
bill_amount = 0.0
allocations_found = {}

if bills:
    bill = bills[0]
    bill_found = True
    bill_amount = bill.get('amount_total', 0.0)
    if abs(bill_amount - 12000.0) < 1.0: # Tolerance for rounding
        bill_correct_amount = True
        
    # Check Analytic Distribution on lines
    line_ids = bill.get('invoice_line_ids', [])
    if line_ids:
        lines = execute('account.move.line', 'read', [line_ids],
            {'fields': ['analytic_distribution', 'price_subtotal']})
        
        # Look for the line with the main cost
        for line in lines:
            if line.get('price_subtotal', 0.0) >= 11000.0: # Ensure we check the main line
                dist = line.get('analytic_distribution')
                # dist is a dict { 'account_id': percentage }
                # Note: Odoo XMLRPC might return keys as strings
                if dist:
                    for acc_id_str, percent in dist.items():
                        # Resolve account name
                        # We need to lookup the name if we haven't already
                        if acc_id_str in account_id_to_name:
                            acc_name = account_id_to_name[acc_id_str]
                            allocations_found[acc_name] = percent
                        else:
                            # Fallback: query account name
                            try:
                                acc_info = execute('account.analytic.account', 'read', [int(acc_id_str)], {'fields': ['name']})
                                if acc_info:
                                    allocations_found[acc_info[0]['name']] = percent
                            except:
                                pass

# Construct Result
result = {
    "plan_found": plan_found,
    "accounts_found_count": len(found_accounts),
    "accounts_found_names": list(found_accounts.keys()),
    "bill_found": bill_found,
    "bill_amount": bill_amount,
    "bill_correct_amount": bill_correct_amount,
    "allocations": allocations_found,
    "timestamp": datetime.now().isoformat()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="