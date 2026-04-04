#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting enable_recurring_revenue results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract data using Python/XML-RPC
python3 - <<PYEOF > /tmp/extraction_log.txt 2>&1
import xmlrpc.client
import json
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "plan_exists": False,
    "plan_correct": False,
    "opp_exists": False,
    "opp_details_correct": False,
    "setting_enabled": False,
    "raw_data": {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check if 'Quarterly' plan exists
    # Model: crm.recurring.plan
    # Fields: name, number_of_months
    try:
        plans = models.execute_kw(db, uid, password, 'crm.recurring.plan', 'search_read', 
            [[['name', '=', 'Quarterly']]], 
            {'fields': ['id', 'name', 'number_of_months']})
        
        if plans:
            result['plan_exists'] = True
            plan = plans[0]
            result['raw_data']['plan'] = plan
            if plan['number_of_months'] == 3:
                result['plan_correct'] = True
    except Exception as e:
        result['raw_data']['plan_error'] = str(e)
        # If model doesn't exist, feature likely not enabled

    # 2. Check Opportunity
    # Model: crm.lead
    # Fields: name, expected_revenue, recurring_revenue, recurring_plan_id
    opps = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
        [[['name', '=', 'Apex Logic - Enterprise Bundle']]],
        {'fields': ['id', 'name', 'expected_revenue', 'recurring_revenue', 'recurring_plan_id']})
    
    if opps:
        result['opp_exists'] = True
        opp = opps[0]
        result['raw_data']['opportunity'] = opp
        
        # Check details
        rev_ok = abs(opp.get('expected_revenue', 0) - 2500.0) < 1.0
        rec_ok = abs(opp.get('recurring_revenue', 0) - 600.0) < 1.0
        
        # Check plan link
        # recurring_plan_id returns [id, name] or False
        plan_link = opp.get('recurring_plan_id')
        plan_linked = False
        if plan_link and isinstance(plan_link, list) and len(plan_link) > 1:
            if 'Quarterly' in plan_link[1]:
                plan_linked = True
        
        result['raw_data']['checks'] = {
            'revenue_ok': rev_ok,
            'recurring_ok': rec_ok,
            'plan_linked': plan_linked
        }

    # 3. Check Setting (Group)
    # We check if the group 'crm.group_use_recurring_revenues' is implied/active
    # Or simply check if we could access crm.recurring.plan above (which we did)
    # Explicit check via config parameters implies checking last write
    # We'll infer setting enabled if plans exist or if we can read the model
    try:
        models.execute_kw(db, uid, password, 'crm.recurring.plan', 'search_count', [[]])
        result['setting_enabled'] = True
    except:
        result['setting_enabled'] = False

except Exception as e:
    print(f"Extraction error: {e}")
    result['error'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Data extraction complete. Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="