#!/bin/bash
echo "=== Setting up new_hire_complete_onboarding task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/onboarding_result.json
rm -f /tmp/onboarding_gt.json

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db = 'odoo_hr'
user = 'admin'
pwd = 'admin'

uid = None
for attempt in range(20):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, user, pwd, {})
        if uid:
            break
    except Exception:
        pass
    time.sleep(5)

if not uid:
    print("ERROR: Could not authenticate to Odoo", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kwargs=None):
    return models.execute_kw(db, uid, pwd, model, method, args, kwargs or {})

def find_employee(name):
    ids = exe('hr.employee', 'search', [[['name', '=', name]]])
    return ids[0] if ids else None

def find_dept(name):
    ids = exe('hr.department', 'search', [[['name', '=', name]]])
    return ids[0] if ids else None

def find_job(name):
    ids = exe('hr.job', 'search', [[['name', '=', name]]])
    return ids[0] if ids else None

# --- Remove existing Jordan Kim employee records ---
existing = exe('hr.employee', 'search', [[['name', '=', 'Jordan Kim']]])
if existing:
    # First remove any allocations
    for emp_id in existing:
        allocs = exe('hr.leave.allocation', 'search', [[['employee_id', '=', emp_id]]])
        if allocs:
            try:
                exe('hr.leave.allocation', 'action_reset_confirm', [allocs])
            except Exception:
                pass
            try:
                exe('hr.leave.allocation', 'unlink', [allocs])
            except Exception as e:
                print(f"Warning: could not remove allocations: {e}", file=sys.stderr)
    exe('hr.employee', 'unlink', [existing])
    print(f"Removed {len(existing)} existing 'Jordan Kim' record(s)")

# --- Create Jordan Kim with ONLY name (blank everything else) ---
jordan_id = exe('hr.employee', 'create', [{
    'name': 'Jordan Kim',
    # Deliberately leave all other fields blank — agent must fill them in
}])
print(f"Created blank employee 'Jordan Kim' (id={jordan_id})")

# --- Verify required reference data exists ---
rd_dept_id = find_dept('Research & Development')
if not rd_dept_id:
    print("WARNING: 'Research & Development' department not found", file=sys.stderr)

marc_id = find_employee('Marc Demo')
if not marc_id:
    print("WARNING: 'Marc Demo' not found", file=sys.stderr)

eli_id = find_employee('Eli Lambert')
if not eli_id:
    print("WARNING: 'Eli Lambert' not found", file=sys.stderr)

exp_dev_job_id = find_job('Experienced Developer')
if not exp_dev_job_id:
    print("WARNING: 'Experienced Developer' job position not found", file=sys.stderr)

# --- Ensure Employee and Trainer tags exist ---
tag_ids = {}
for tag_name in ['Employee', 'Trainer']:
    existing_tags = exe('hr.employee.category', 'search', [[['name', '=', tag_name]]])
    if existing_tags:
        tag_ids[tag_name] = existing_tags[0]
    else:
        tag_id = exe('hr.employee.category', 'create', [{'name': tag_name}])
        tag_ids[tag_name] = tag_id
        print(f"Created tag '{tag_name}' (id={tag_id})")
    print(f"Tag '{tag_name}' id={tag_ids[tag_name]}")

# --- Get PTO and Compensatory Days leave types ---
pto_types = exe('hr.leave.type', 'search_read',
                [[['name', 'ilike', 'Paid Time Off']]],
                {'fields': ['id', 'name'], 'limit': 1})
pto_type_id = pto_types[0]['id'] if pto_types else None

comp_types = exe('hr.leave.type', 'search_read',
                 [[['name', 'ilike', 'Compensatory']]],
                 {'fields': ['id', 'name'], 'limit': 1})
comp_type_id = comp_types[0]['id'] if comp_types else None

print(f"PTO type id={pto_type_id}, Comp type id={comp_type_id}")

# Save ground truth
gt = {
    'jordan_kim_id': jordan_id,
    'rd_dept_id': rd_dept_id,
    'marc_demo_id': marc_id,
    'eli_lambert_id': eli_id,
    'exp_dev_job_id': exp_dev_job_id,
    'employee_tag_id': tag_ids.get('Employee'),
    'trainer_tag_id': tag_ids.get('Trainer'),
    'pto_type_id': pto_type_id,
    'comp_type_id': comp_type_id,
    'expected_work_phone': '+1 555 234 5678',
    'expected_work_email': 'jordan.kim@company.com',
    'expected_pto_days': 20,
    'expected_comp_days': 5,
}
with open('/tmp/onboarding_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"\nSetup complete: Jordan Kim (id={jordan_id}) created with blank profile.")
print("Agent must fill in all required fields, add tags, and create allocations.")
PYTHON_EOF

date +%s > /tmp/task_start_timestamp
date +%s > /tmp/onboarding_start_ts

# Baseline recording (Pattern 1): Jordan Kim's initial blank state
python3 -c "
import xmlrpc.client, json
url='http://localhost:8069'; db='odoo_hr'; pwd='admin'
common=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid=common.authenticate(db,'admin',pwd,{})
models=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
with open('/tmp/onboarding_gt.json') as f: gt=json.load(f)
emp=models.execute_kw(db,uid,pwd,'hr.employee','read',[[gt['jordan_kim_id']]],
  {'fields':['job_id','department_id','parent_id','work_email','category_ids']})[0]
filled=(1 if emp.get('job_id') else 0)+(1 if emp.get('department_id') else 0)+(1 if emp.get('work_email') else 0)
with open('/tmp/initial_jordan_fields_count','w') as f: f.write(str(filled))
print(f'Baseline: {filled} fields filled on Jordan Kim (expect 0)')
" 2>/dev/null || echo "0" > /tmp/initial_jordan_fields_count

ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 3

take_screenshot /tmp/onboarding_start.png

echo "Task start: Agent must complete Jordan Kim's onboarding profile."
echo "=== new_hire_complete_onboarding setup complete ==="
