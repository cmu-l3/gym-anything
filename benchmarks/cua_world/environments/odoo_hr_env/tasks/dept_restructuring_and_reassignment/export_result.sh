#!/bin/bash
echo "=== Exporting dept_restructuring_and_reassignment results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/dept_restructuring_end.png

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
    with open('/tmp/dept_restructuring_result.json', 'w') as f:
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
    with open('/tmp/dept_restructuring_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/dept_restructuring_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

rdu_id = gt['rdu_dept_id']
rd_id = gt['rd_dept_id']
marc_id = gt['marc_demo_id']
target_ids = gt['target_employee_ids']

# Check R&D USA department active status (search with active_test=False)
rdu_dept = exe('hr.department', 'search_read',
               [[['id', '=', rdu_id], ['active', 'in', [True, False]]]],
               {'fields': ['name', 'active'], 'context': {'active_test': False}})
rdu_active = rdu_dept[0]['active'] if rdu_dept else True  # default True (not archived)

# Check each target employee
employee_results = []
for emp_id in target_ids:
    emps = exe('hr.employee', 'read', [[emp_id]], {'fields': ['name', 'department_id', 'parent_id']})
    if emps:
        e = emps[0]
        dept_id = e['department_id'][0] if e.get('department_id') else None
        parent_id = e['parent_id'][0] if e.get('parent_id') else None
        employee_results.append({
            'id': emp_id,
            'name': e.get('name', ''),
            'department_id': dept_id,
            'department_name': e['department_id'][1] if e.get('department_id') else '',
            'parent_id': parent_id,
            'parent_name': e['parent_id'][1] if e.get('parent_id') else '',
            'in_rd': dept_id == rd_id,
            'has_marc_manager': parent_id == marc_id,
        })

result = {
    'rdu_dept_id': rdu_id,
    'rd_dept_id': rd_id,
    'marc_demo_id': marc_id,
    'rdu_department_archived': not rdu_active,
    'target_count': len(target_ids),
    'employees': employee_results,
}

with open('/tmp/dept_restructuring_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/dept_restructuring_result.json 2>/dev/null || true
echo "=== dept_restructuring_and_reassignment export complete ==="
