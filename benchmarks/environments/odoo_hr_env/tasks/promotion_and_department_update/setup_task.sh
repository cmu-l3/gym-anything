#!/bin/bash
echo "=== Setting up promotion_and_department_update task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/promotion_result.json
rm -f /tmp/promotion_gt.json

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

# --- Get departments ---
mgmt_dept_id = find_dept('Management')
ltp_dept_id = find_dept('Long Term Projects')
rnd_dept_id = find_dept('Research & Development')
rdu_dept_id = find_dept('R&D USA')

if not ltp_dept_id:
    ltp_dept_id = exe('hr.department', 'create', [{'name': 'Long Term Projects'}])
    print(f"Created 'Long Term Projects' dept (id={ltp_dept_id})")
else:
    print(f"Found 'Long Term Projects' dept (id={ltp_dept_id})")

if not mgmt_dept_id:
    mgmt_dept_id = exe('hr.department', 'create', [{'name': 'Management'}])
    print(f"Created 'Management' dept (id={mgmt_dept_id})")
else:
    print(f"Found 'Management' dept (id={mgmt_dept_id})")

# --- Get job positions ---
cto_job_id = find_job('CTO')
exp_dev_job_id = find_job('Experienced Developer')
consultant_job_id = find_job('Consultant')
hr_mgr_job_id = find_job('HR Manager')

if not hr_mgr_job_id:
    hr_mgr_job_id = exe('hr.job', 'create', [{'name': 'HR Manager', 'department_id': mgmt_dept_id}])
    print(f"Created 'HR Manager' job position (id={hr_mgr_job_id})")

print(f"CTO job id={cto_job_id}, Exp Dev job id={exp_dev_job_id}, HR Mgr job id={hr_mgr_job_id}")

# --- Get employees ---
ronnie_id = find_employee('Ronnie Hart')
jennie_id = find_employee('Jennie Fletcher')
randall_id = find_employee('Randall Lewis')
ernest_id = find_employee('Ernest Reed')
paul_id = find_employee('Paul Williams')
marc_id = find_employee('Marc Demo')

# --- Set Ronnie Hart to NON-CTO, NON-Management state (so agent must change it) ---
if ronnie_id:
    vals = {}
    if exp_dev_job_id:
        vals['job_id'] = exp_dev_job_id  # NOT CTO
    if rnd_dept_id:
        vals['department_id'] = rnd_dept_id  # NOT Management
    if vals:
        exe('hr.employee', 'write', [[ronnie_id], vals])
    print(f"Set Ronnie Hart to Experienced Developer in R&D (NOT CTO, NOT Management)")

# --- Set Jennie Fletcher to non-HR Manager position ---
if jennie_id:
    vals = {}
    if consultant_job_id:
        vals['job_id'] = consultant_job_id  # NOT HR Manager
    elif exp_dev_job_id:
        vals['job_id'] = exp_dev_job_id
    if vals:
        exe('hr.employee', 'write', [[jennie_id], vals])
    print(f"Set Jennie Fletcher to Consultant (NOT HR Manager)")

# --- Set LTP employees: Randall Lewis, Ernest Reed, Paul Williams ---
ltp_employees = []
for name, emp_id in [('Randall Lewis', randall_id), ('Ernest Reed', ernest_id), ('Paul Williams', paul_id)]:
    if emp_id:
        exe('hr.employee', 'write', [[emp_id], {'department_id': ltp_dept_id}])
        ltp_employees.append(emp_id)
        print(f"Set '{name}' (id={emp_id}) to Long Term Projects")

# --- Ensure Consultant tag exists ---
consultant_tag_ids = exe('hr.employee.category', 'search', [[['name', '=', 'Consultant']]])
if consultant_tag_ids:
    consultant_tag_id = consultant_tag_ids[0]
else:
    consultant_tag_id = exe('hr.employee.category', 'create', [{'name': 'Consultant'}])
    print(f"Created 'Consultant' tag (id={consultant_tag_id})")
print(f"'Consultant' tag id={consultant_tag_id}")

# --- Remove Consultant tag from all LTP employees (agent must add it back) ---
for emp_id in ltp_employees:
    exe('hr.employee', 'write', [[emp_id], {
        'category_ids': [(3, consultant_tag_id)],  # 3 = unlink
    }])
print(f"Removed Consultant tag from {len(ltp_employees)} LTP employees")

# --- Ensure LTP dept manager is NOT Randall Lewis (agent must set it) ---
if ltp_dept_id:
    # Set a different manager for LTP dept (use admin user employee, or clear it)
    current_dept = exe('hr.department', 'read', [[ltp_dept_id]], {'fields': ['manager_id']})
    if current_dept:
        current_mgr = current_dept[0].get('manager_id')
        if current_mgr and (isinstance(current_mgr, (list, tuple)) and current_mgr[0] == randall_id):
            # Clear the manager so it's not pre-set to Randall
            exe('hr.department', 'write', [[ltp_dept_id], {'manager_id': False}])
            print("Cleared LTP department manager (was Randall Lewis)")

# --- Ensure Marc Demo is in Management department ---
if marc_id and mgmt_dept_id:
    exe('hr.employee', 'write', [[marc_id], {'department_id': mgmt_dept_id}])
    print(f"Confirmed Marc Demo is in Management department")

# Save ground truth
gt = {
    'ronnie_hart_id': ronnie_id,
    'jennie_fletcher_id': jennie_id,
    'randall_lewis_id': randall_id,
    'marc_demo_id': marc_id,
    'cto_job_id': cto_job_id,
    'hr_mgr_job_id': hr_mgr_job_id,
    'mgmt_dept_id': mgmt_dept_id,
    'ltp_dept_id': ltp_dept_id,
    'consultant_tag_id': consultant_tag_id,
    'ltp_employee_ids': ltp_employees,
    'ltp_employee_names': ['Randall Lewis', 'Ernest Reed', 'Paul Williams'],
}
with open('/tmp/promotion_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"\nSetup complete:")
print(f"  Ronnie Hart: needs CTO + Management (currently Experienced Developer + R&D)")
print(f"  Jennie Fletcher: needs HR Manager (currently Consultant)")
print(f"  LTP employees ({len(ltp_employees)}): need Consultant tag (currently removed)")
print(f"  LTP dept: needs Randall Lewis as manager")
PYTHON_EOF

date +%s > /tmp/task_start_timestamp
date +%s > /tmp/promotion_start_ts

# Baseline recording (Pattern 1): record initial state before agent acts
python3 -c "
import xmlrpc.client, json
url='http://localhost:8069'; db='odoo_hr'; pwd='admin'
common=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid=common.authenticate(db,'admin',pwd,{})
models=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
with open('/tmp/promotion_gt.json') as f: gt=json.load(f)
# Count LTP employees with consultant tag (expect 0 after setup)
count=models.execute_kw(db,uid,pwd,'hr.employee','search_count',
  [[['id','in',gt['ltp_employee_ids']],
    ['category_ids','in',[gt['consultant_tag_id']]]]])
with open('/tmp/initial_ltp_consultant_count','w') as f: f.write(str(count))
print(f'Baseline: {count} LTP employees with Consultant tag (expect 0)')
" 2>/dev/null || echo "0" > /tmp/initial_ltp_consultant_count

ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 3

take_screenshot /tmp/promotion_start.png

echo "Task start: Agent must implement 4 personnel changes from annual review."
echo "=== promotion_and_department_update setup complete ==="
