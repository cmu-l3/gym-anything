#!/bin/bash
echo "=== Setting up annual_leave_audit_and_correction task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/leave_audit_result.json
rm -f /tmp/leave_audit_gt.json

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

# --- Ensure Sales department exists ---
sales_dept_id = find_dept('Sales')
if not sales_dept_id:
    sales_dept_id = exe('hr.department', 'create', [{'name': 'Sales'}])
    print(f"Created 'Sales' department (id={sales_dept_id})")
else:
    print(f"Found 'Sales' department (id={sales_dept_id})")

# --- Get or create Sales employee tag ---
tag_ids = exe('hr.employee.category', 'search', [[['name', '=', 'Sales']]])
if tag_ids:
    sales_tag_id = tag_ids[0]
else:
    sales_tag_id = exe('hr.employee.category', 'create', [{'name': 'Sales'}])
print(f"'Sales' tag id={sales_tag_id}")

# --- Set up 4 target employees in Sales department ---
target_names = ['Keith Byrd', 'Doris Cole', 'Tina Williamson', 'Toni Jimenez']
target_ids = []

for name in target_names:
    emp_id = find_employee(name)
    if emp_id:
        # Move to Sales department and clear Sales tag (agent must add it back)
        exe('hr.employee', 'write', [[emp_id], {
            'department_id': sales_dept_id,
            'category_ids': [(3, sales_tag_id)],  # 3 = unlink (remove) the tag
        }])
        target_ids.append(emp_id)
        print(f"Set '{name}' (id={emp_id}) to Sales dept, removed Sales tag")
    else:
        print(f"WARNING: '{name}' not found", file=sys.stderr)

# --- Get Paid Time Off leave type ---
pto_types = exe('hr.leave.type', 'search_read',
                [[['name', 'ilike', 'Paid Time Off']]],
                {'fields': ['id', 'name'], 'limit': 1})
if not pto_types:
    pto_types = exe('hr.leave.type', 'search_read',
                    [[['requires_allocation', '=', 'yes']]],
                    {'fields': ['id', 'name'], 'limit': 1})
if not pto_types:
    print("ERROR: Could not find Paid Time Off leave type", file=sys.stderr)
    sys.exit(1)
pto_type_id = pto_types[0]['id']
pto_type_name = pto_types[0]['name']
print(f"Using leave type: '{pto_type_name}' (id={pto_type_id})")

# --- Reset PTO allocations: remove ALL existing ones for the 4 target employees ---
for emp_id in target_ids:
    existing_allocs = exe('hr.leave.allocation', 'search',
                          [[['employee_id', '=', emp_id],
                            ['holiday_status_id', '=', pto_type_id]]])
    if existing_allocs:
        try:
            # Reset to draft before unlinking
            draft_allocs = exe('hr.leave.allocation', 'search',
                               [[['id', 'in', existing_allocs],
                                 ['state', 'not in', ['draft']]]])
            if draft_allocs:
                try:
                    exe('hr.leave.allocation', 'action_reset_confirm', [draft_allocs])
                except Exception:
                    pass
            exe('hr.leave.allocation', 'unlink', [existing_allocs])
            print(f"Removed {len(existing_allocs)} PTO allocations for emp_id={emp_id}")
        except Exception as e:
            print(f"Warning: Could not remove PTO allocations for {emp_id}: {e}", file=sys.stderr)

# --- Create insufficient allocations for Doris Cole and Tina Williamson ---
# (agent must correct these; Keith Byrd and Toni Jimenez have no PTO allocation at all)
insufficient_employees = {
    'Doris Cole': 10,    # has 10 days, needs 20
    'Tina Williamson': 5, # has 5 days, needs 20
}

for name, days in insufficient_employees.items():
    emp_id = find_employee(name)
    if emp_id:
        try:
            alloc_id = exe('hr.leave.allocation', 'create', [{
                'holiday_status_id': pto_type_id,
                'employee_id': emp_id,
                'number_of_days': days,
                'name': f'Annual PTO allocation (partial)',
                'allocation_type': 'regular',
            }])
            # Approve the allocation
            try:
                exe('hr.leave.allocation', 'action_validate', [[alloc_id]])
            except Exception:
                try:
                    exe('hr.leave.allocation', 'action_confirm', [[alloc_id]])
                    exe('hr.leave.allocation', 'action_validate', [[alloc_id]])
                except Exception as e2:
                    print(f"Warning: Could not validate allocation for {name}: {e2}", file=sys.stderr)
            print(f"Created {days}-day PTO allocation for '{name}' (insufficient — agent must correct)")
        except Exception as e:
            print(f"Warning: Could not create allocation for {name}: {e}", file=sys.stderr)

# Save ground truth
gt = {
    'sales_dept_id': sales_dept_id,
    'sales_tag_id': sales_tag_id,
    'pto_type_id': pto_type_id,
    'pto_type_name': pto_type_name,
    'target_employee_ids': target_ids,
    'target_names': target_names[:len(target_ids)],
    'required_days': 20,
}
with open('/tmp/leave_audit_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"\nSetup complete: {len(target_ids)} Sales employees with PTO deficiencies.")
print("Agent must audit and correct all deficiencies.")
PYTHON_EOF

date +%s > /tmp/task_start_timestamp
date +%s > /tmp/leave_audit_start_ts

# Baseline recording (Pattern 1): initial count of Sales employees with sufficient PTO (expect 0)
python3 -c "
import xmlrpc.client, json
url='http://localhost:8069'; db='odoo_hr'; pwd='admin'
common=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid=common.authenticate(db,'admin',pwd,{})
models=xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
with open('/tmp/leave_audit_gt.json') as f: gt=json.load(f)
count=models.execute_kw(db,uid,pwd,'hr.leave.allocation','search_count',
  [[['employee_id','in',gt['target_employee_ids']],
    ['holiday_status_id','=',gt['pto_type_id']],
    ['number_of_days','>=',20],['state','in',['validate','validate1']]]])
with open('/tmp/initial_sufficient_pto_count','w') as f: f.write(str(count))
print(f'Baseline: {count} employees with sufficient PTO (expect 0)')
" 2>/dev/null || echo "0" > /tmp/initial_sufficient_pto_count

ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"
sleep 3

take_screenshot /tmp/leave_audit_start.png

echo "Task start: Agent must audit Sales dept leave allocations and tags."
echo "=== annual_leave_audit_and_correction setup complete ==="
