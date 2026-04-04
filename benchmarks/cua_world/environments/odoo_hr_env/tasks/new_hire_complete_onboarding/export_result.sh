#!/bin/bash
echo "=== Exporting new_hire_complete_onboarding results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/onboarding_end.png

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
    with open('/tmp/onboarding_result.json', 'w') as f:
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
    with open('/tmp/onboarding_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/onboarding_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

jordan_id = gt['jordan_kim_id']
pto_type_id = gt.get('pto_type_id')
comp_type_id = gt.get('comp_type_id')

# Read Jordan Kim's current profile
emp_data = exe('hr.employee', 'read', [[jordan_id]],
               {'fields': ['name', 'job_id', 'department_id', 'parent_id',
                           'coach_id', 'work_phone', 'work_email', 'category_ids']})
if not emp_data:
    with open('/tmp/onboarding_result.json', 'w') as f:
        json.dump({'error': 'jordan_kim_not_found'}, f)
    sys.exit(0)

emp = emp_data[0]

def get_id(field_val):
    if isinstance(field_val, (list, tuple)) and len(field_val) >= 1:
        return field_val[0]
    return None

def get_name(field_val):
    if isinstance(field_val, (list, tuple)) and len(field_val) >= 2:
        return field_val[1]
    return None

job_id = get_id(emp.get('job_id'))
dept_id = get_id(emp.get('department_id'))
manager_id = get_id(emp.get('parent_id'))
coach_id = get_id(emp.get('coach_id'))
tag_ids = emp.get('category_ids', [])

# Check PTO allocation
pto_allocs = []
if pto_type_id:
    pto_allocs = exe('hr.leave.allocation', 'search_read',
                     [[['employee_id', '=', jordan_id],
                       ['holiday_status_id', '=', pto_type_id],
                       ['state', 'in', ['validate', 'validate1']]]],
                     {'fields': ['number_of_days']}) or []

# Check Compensatory Days allocation
comp_allocs = []
if comp_type_id:
    comp_allocs = exe('hr.leave.allocation', 'search_read',
                      [[['employee_id', '=', jordan_id],
                        ['holiday_status_id', '=', comp_type_id],
                        ['state', 'in', ['validate', 'validate1']]]],
                      {'fields': ['number_of_days']}) or []

max_pto = max((a['number_of_days'] for a in pto_allocs), default=0) if pto_allocs else 0
max_comp = max((a['number_of_days'] for a in comp_allocs), default=0) if comp_allocs else 0

result = {
    'jordan_kim_id': jordan_id,
    'job_id': job_id,
    'job_name': get_name(emp.get('job_id')),
    'dept_id': dept_id,
    'dept_name': get_name(emp.get('department_id')),
    'manager_id': manager_id,
    'manager_name': get_name(emp.get('parent_id')),
    'coach_id': coach_id,
    'coach_name': get_name(emp.get('coach_id')),
    'work_phone': emp.get('work_phone') or '',
    'work_email': emp.get('work_email') or '',
    'tag_ids': tag_ids,
    'max_pto_days': max_pto,
    'max_comp_days': max_comp,
    # Ground truth references for verifier
    'expected_job_id': gt.get('exp_dev_job_id'),
    'expected_dept_id': gt.get('rd_dept_id'),
    'expected_manager_id': gt.get('marc_demo_id'),
    'expected_coach_id': gt.get('eli_lambert_id'),
    'expected_employee_tag_id': gt.get('employee_tag_id'),
    'expected_trainer_tag_id': gt.get('trainer_tag_id'),
    'expected_pto_days': gt.get('expected_pto_days', 20),
    'expected_comp_days': gt.get('expected_comp_days', 5),
}

with open('/tmp/onboarding_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/onboarding_result.json 2>/dev/null || true
echo "=== new_hire_complete_onboarding export complete ==="
