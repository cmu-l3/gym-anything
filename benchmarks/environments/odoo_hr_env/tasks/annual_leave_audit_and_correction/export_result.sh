#!/bin/bash
echo "=== Exporting annual_leave_audit_and_correction results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/leave_audit_end.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db = 'odoo_hr'
user = 'admin'
pwd = 'admin'

uid = None
for attempt in range(10):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, user, pwd, {})
        if uid:
            break
    except Exception:
        pass
    time.sleep(3)

if not uid:
    with open('/tmp/leave_audit_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kwargs=None):
    try:
        return models.execute_kw(db, uid, pwd, model, method, args, kwargs or {})
    except Exception:
        return None

# Load ground truth
try:
    with open('/tmp/leave_audit_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/leave_audit_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

pto_type_id = gt['pto_type_id']
sales_tag_id = gt['sales_tag_id']
required_days = gt['required_days']
target_ids = gt['target_employee_ids']

employee_results = []
for emp_id in target_ids:
    emps = exe('hr.employee', 'read', [[emp_id]], {'fields': ['name', 'department_id', 'category_ids']})
    if not emps:
        continue
    e = emps[0]

    # Check PTO allocations: find max days across all validated allocations
    allocs = exe('hr.leave.allocation', 'search_read',
                 [[['employee_id', '=', emp_id],
                   ['holiday_status_id', '=', pto_type_id],
                   ['state', 'in', ['validate', 'validate1']]]],
                 {'fields': ['number_of_days', 'state']})
    max_pto_days = max((a['number_of_days'] for a in allocs), default=0) if allocs else 0
    has_sufficient_pto = max_pto_days >= required_days

    # Check Sales tag
    has_sales_tag = sales_tag_id in (e.get('category_ids') or [])

    employee_results.append({
        'id': emp_id,
        'name': e.get('name', ''),
        'max_pto_days': max_pto_days,
        'has_sufficient_pto': has_sufficient_pto,
        'has_sales_tag': has_sales_tag,
        'allocation_count': len(allocs) if allocs else 0,
    })

result = {
    'pto_type_id': pto_type_id,
    'sales_tag_id': sales_tag_id,
    'required_days': required_days,
    'target_count': len(target_ids),
    'employees': employee_results,
}

with open('/tmp/leave_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/leave_audit_result.json 2>/dev/null || true
echo "=== annual_leave_audit_and_correction export complete ==="
