#!/bin/bash
echo "=== Exporting promotion_and_department_update results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/promotion_end.png

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
    with open('/tmp/promotion_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kwargs=None):
    try:
        return models.execute_kw(db, uid, pwd, model, method, args, kwargs or {})
    except Exception:
        return None

def get_id(val):
    return val[0] if isinstance(val, (list, tuple)) and len(val) >= 1 else None

def get_name(val):
    return val[1] if isinstance(val, (list, tuple)) and len(val) >= 2 else None

# Load ground truth
try:
    with open('/tmp/promotion_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/promotion_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

ronnie_id = gt['ronnie_hart_id']
jennie_id = gt['jennie_fletcher_id']
randall_id = gt['randall_lewis_id']
ltp_emp_ids = gt['ltp_employee_ids']
ltp_dept_id = gt['ltp_dept_id']
consultant_tag_id = gt['consultant_tag_id']

# Check Ronnie Hart
ronnie_result = {}
if ronnie_id:
    data = exe('hr.employee', 'read', [[ronnie_id]],
               {'fields': ['name', 'job_id', 'department_id', 'parent_id']})
    if data:
        e = data[0]
        ronnie_result = {
            'job_id': get_id(e.get('job_id')),
            'job_name': get_name(e.get('job_id')),
            'dept_id': get_id(e.get('department_id')),
            'dept_name': get_name(e.get('department_id')),
            'manager_id': get_id(e.get('parent_id')),
            'manager_name': get_name(e.get('parent_id')),
            'has_cto': get_id(e.get('job_id')) == gt['cto_job_id'],
            'in_management': get_id(e.get('department_id')) == gt['mgmt_dept_id'],
            'has_marc_manager': get_id(e.get('parent_id')) == gt['marc_demo_id'],
        }

# Check Jennie Fletcher
jennie_result = {}
if jennie_id:
    data = exe('hr.employee', 'read', [[jennie_id]], {'fields': ['name', 'job_id']})
    if data:
        e = data[0]
        jennie_result = {
            'job_id': get_id(e.get('job_id')),
            'job_name': get_name(e.get('job_id')),
            'has_hr_mgr': get_id(e.get('job_id')) == gt['hr_mgr_job_id'],
        }

# Check LTP employees have Consultant tag
ltp_results = []
for emp_id in ltp_emp_ids:
    data = exe('hr.employee', 'read', [[emp_id]], {'fields': ['name', 'category_ids']})
    if data:
        e = data[0]
        tag_ids = e.get('category_ids', [])
        ltp_results.append({
            'id': emp_id,
            'name': e.get('name', ''),
            'has_consultant_tag': consultant_tag_id in tag_ids,
        })

# Check LTP department manager
ltp_dept_result = {}
if ltp_dept_id:
    data = exe('hr.department', 'read', [[ltp_dept_id]], {'fields': ['name', 'manager_id']})
    if data:
        d = data[0]
        ltp_dept_result = {
            'manager_id': get_id(d.get('manager_id')),
            'manager_name': get_name(d.get('manager_id')),
            'has_randall_manager': get_id(d.get('manager_id')) == randall_id,
        }

result = {
    'ronnie_hart': ronnie_result,
    'jennie_fletcher': jennie_result,
    'ltp_employees': ltp_results,
    'ltp_dept': ltp_dept_result,
    'ltp_total': len(ltp_emp_ids),
    # Pass ground truth through for verifier
    'cto_job_id': gt['cto_job_id'],
    'hr_mgr_job_id': gt['hr_mgr_job_id'],
    'mgmt_dept_id': gt['mgmt_dept_id'],
    'marc_demo_id': gt['marc_demo_id'],
    'randall_lewis_id': randall_id,
    'consultant_tag_id': consultant_tag_id,
}

with open('/tmp/promotion_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/promotion_result.json 2>/dev/null || true
echo "=== promotion_and_department_update export complete ==="
