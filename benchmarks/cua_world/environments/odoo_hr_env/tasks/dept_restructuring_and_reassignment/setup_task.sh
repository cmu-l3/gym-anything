#!/bin/bash
echo "=== Setting up dept_restructuring_and_reassignment task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/dept_restructuring_result.json
rm -f /tmp/dept_restructuring_gt.json

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
    # Search including archived departments
    ids = exe('hr.department', 'search', [[['name', '=', name], ['active', 'in', [True, False]]]])
    return ids[0] if ids else None

# --- Ensure R&D USA department exists and is active ---
rdu_id = find_dept('R&D USA')
if not rdu_id:
    # Get Research & Development as parent
    rd_id = find_dept('Research & Development')
    rdu_id = exe('hr.department', 'create', [{'name': 'R&D USA', 'parent_id': rd_id}])
    print(f"Created 'R&D USA' department (id={rdu_id})")
else:
    # Unarchive if archived
    exe('hr.department', 'write', [[rdu_id], {'active': True}])
    print(f"Ensured 'R&D USA' is active (id={rdu_id})")

# --- Get Research & Development department ---
rd_id = find_dept('Research & Development')
if not rd_id:
    print("ERROR: 'Research & Development' department not found", file=sys.stderr)
    sys.exit(1)
print(f"Found 'Research & Development' department (id={rd_id})")

# --- Get Marc Demo employee ---
marc_id = find_employee('Marc Demo')
if not marc_id:
    print("ERROR: 'Marc Demo' employee not found", file=sys.stderr)
    sys.exit(1)
print(f"Found 'Marc Demo' (id={marc_id})")

# --- Set target employees to R&D USA with a non-Marc-Demo manager ---
# Use Walter Horton, Beth Evans, Toni Jimenez as the R&D USA employees
target_names = ['Walter Horton', 'Beth Evans', 'Toni Jimenez']
target_ids = []

# Find a different manager (not Marc Demo) to set for each — use Eli Lambert
eli_id = find_employee('Eli Lambert')

for name in target_names:
    emp_id = find_employee(name)
    if emp_id:
        vals = {
            'department_id': rdu_id,
        }
        if eli_id and eli_id != marc_id:
            vals['parent_id'] = eli_id  # Set to Eli, NOT Marc — agent must change this
        exe('hr.employee', 'write', [[emp_id], vals])
        target_ids.append(emp_id)
        print(f"Placed '{name}' (id={emp_id}) in R&D USA with manager Eli Lambert")
    else:
        print(f"WARNING: Employee '{name}' not found — skipping", file=sys.stderr)

# --- Ensure Marc Demo is in Research & Development ---
exe('hr.employee', 'write', [[marc_id], {'department_id': rd_id}])
print(f"Confirmed Marc Demo is in Research & Development")

# --- Remove any other employees accidentally in R&D USA (keep only the 3 targets) ---
all_rdu = exe('hr.employee', 'search', [[['department_id', '=', rdu_id]]])
extras = [e for e in all_rdu if e not in target_ids]
if extras:
    # Move extras to Research & Development so only target employees are in R&D USA
    exe('hr.employee', 'write', [extras, {'department_id': rd_id}])
    print(f"Moved {len(extras)} extra employees out of R&D USA")

# Save ground truth
gt = {
    'rdu_dept_id': rdu_id,
    'rd_dept_id': rd_id,
    'marc_demo_id': marc_id,
    'target_employee_ids': target_ids,
    'target_employee_names': target_names[:len(target_ids)],
}
with open('/tmp/dept_restructuring_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"\nGround truth saved: {len(target_ids)} target employees in R&D USA")
print(f"Agent must discover employees and move them — not told who they are.")
PYTHON_EOF

date +%s > /tmp/task_start_timestamp
date +%s > /tmp/dept_restructuring_start_ts

# Baseline recording (Pattern 1): record initial R&D USA employee count after cleanup
python3 -c "
import xmlrpc.client, json
url='http://localhost:8069'; db='odoo_hr'; pwd='admin'
common=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid=common.authenticate(db,'admin',pwd,{})
models=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
with open('/tmp/dept_restructuring_gt.json') as f: gt=json.load(f)
count=models.execute_kw(db,uid,pwd,'hr.employee','search_count',[[['department_id','=',gt['rdu_dept_id']]]])
with open('/tmp/initial_rdu_employee_count','w') as f: f.write(str(count))
print(f'Baseline: {count} employees in R&D USA (expect 3)')
" 2>/dev/null || echo "3" > /tmp/initial_rdu_employee_count

ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 3

take_screenshot /tmp/dept_restructuring_start.png

echo "Task start: Agent must find R&D USA employees and restructure."
echo "=== dept_restructuring_and_reassignment setup complete ==="
