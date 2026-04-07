#!/bin/bash
# Export verification data for delete_calendar_event
source /workspace/scripts/task_utils.sh

echo "=== Exporting delete_calendar_event results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data from Odoo
python3 << 'PYEOF'
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
baseline_file = '/tmp/delete_event_baseline.json'

result = {
    'odoo_accessible': False,
    'baseline_loaded': False,
    'final_total_count': 0,
    'target_still_exists_by_id': False,
    'target_still_exists_by_name': False,
    'count_delta': 0
}

# Load baseline
if os.path.exists(baseline_file):
    try:
        with open(baseline_file, 'r') as f:
            baseline = json.load(f)
            result['baseline'] = baseline
            result['baseline_loaded'] = True
    except Exception as e:
        print(f"Error loading baseline: {e}", file=sys.stderr)

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    result['odoo_accessible'] = True
    
    # 1. Check total count
    final_count = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_count', [[]])
    result['final_total_count'] = final_count
    
    if result['baseline_loaded']:
        result['count_delta'] = final_count - baseline['total_event_count']
        
        # 2. Check specific ID existence
        target_id = baseline['target_event_id']
        exists_id = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_count', [[['id', '=', target_id]]])
        result['target_still_exists_by_id'] = (exists_id > 0)
        
        # 3. Check name existence (fallback if ID changed but recreated?)
        target_name = baseline['target_event_name']
        exists_name = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_count', [[['name', '=', target_name]]])
        result['target_still_exists_by_name'] = (exists_name > 0)

except Exception as e:
    print(f"Odoo Query Error: {e}", file=sys.stderr)
    result['error'] = str(e)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="