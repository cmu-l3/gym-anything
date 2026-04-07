#!/bin/bash
echo "=== Setting up implement_rnd_innovation_day task ==="

# Source shared utilities (also ensures Odoo is running)
source /workspace/scripts/task_utils.sh

# Clean stale output files BEFORE recording timestamp
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# -------------------------------------------------------
# Clean State: Remove any existing R&D Innovation Day artifacts
# Order: leave requests -> allocations -> accrual plans -> leave type
# -------------------------------------------------------
echo "Ensuring clean state via XML-RPC..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

retries = 10
uid = None
common = None
models = None

for attempt in range(retries):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        if uid:
            models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
            break
    except Exception as e:
        print(f"Attempt {attempt+1}/{retries}: {e}")
        import time
        time.sleep(5)

if not uid:
    print("ERROR: Could not authenticate with Odoo after retries", file=sys.stderr)
    sys.exit(1)

def exe(model, method, *args, **kwargs):
    return models.execute_kw(db, uid, password, model, method, *args, **kwargs)

print("Authenticated successfully.")

# --- Step 1: Find the "R&D Innovation Day" leave type (if exists) ---
lt_ids = exe('hr.leave.type', 'search', [[['name', 'ilike', 'R&D Innovation Day']]])
# Also search with active=False in case it was archived
lt_ids_inactive = exe('hr.leave.type', 'search', [[['name', 'ilike', 'R&D Innovation Day'], ['active', '=', False]]])
all_lt_ids = list(set(lt_ids + lt_ids_inactive))

if all_lt_ids:
    print(f"Found {len(all_lt_ids)} existing 'R&D Innovation Day' leave type(s). Cleaning up...")

    # --- Step 2: Delete leave requests linked to this type ---
    leave_req_ids = exe('hr.leave', 'search', [[['holiday_status_id', 'in', all_lt_ids]]])
    if leave_req_ids:
        # Must refuse and reset to draft before deleting non-draft requests
        for req_id in leave_req_ids:
            try:
                exe('hr.leave', 'action_refuse', [[req_id]])
            except:
                pass
            try:
                exe('hr.leave', 'action_draft', [[req_id]])
            except:
                pass
        try:
            exe('hr.leave', 'unlink', [leave_req_ids])
            print(f"  Deleted {len(leave_req_ids)} leave request(s)")
        except Exception as e:
            print(f"  Warning deleting leave requests: {e}")

    # --- Step 3: Delete allocations linked to this type ---
    alloc_ids = exe('hr.leave.allocation', 'search', [[['holiday_status_id', 'in', all_lt_ids]]])
    if alloc_ids:
        for alloc_id in alloc_ids:
            try:
                exe('hr.leave.allocation', 'action_refuse', [[alloc_id]])
            except:
                pass
        try:
            exe('hr.leave.allocation', 'unlink', [alloc_ids])
            print(f"  Deleted {len(alloc_ids)} allocation(s)")
        except Exception as e:
            print(f"  Warning deleting allocations: {e}")

    # --- Step 4: Delete the leave type itself ---
    for lt_id in all_lt_ids:
        try:
            exe('hr.leave.type', 'write', [[lt_id], {'active': False}])
            exe('hr.leave.type', 'unlink', [[lt_id]])
            print(f"  Deleted leave type id={lt_id}")
        except Exception as e:
            print(f"  Warning deleting leave type {lt_id}: {e}")

# --- Step 5: Delete accrual plan "R&D Innovation Accrual" ---
plan_ids = exe('hr.leave.accrual.plan', 'search', [[['name', 'ilike', 'R&D Innovation Accrual']]])
if plan_ids:
    # Delete linked allocations first
    linked_allocs = exe('hr.leave.allocation', 'search', [[['accrual_plan_id', 'in', plan_ids]]])
    if linked_allocs:
        for alloc_id in linked_allocs:
            try:
                exe('hr.leave.allocation', 'action_refuse', [[alloc_id]])
            except:
                pass
        try:
            exe('hr.leave.allocation', 'unlink', [linked_allocs])
        except:
            pass
    exe('hr.leave.accrual.plan', 'unlink', [plan_ids])
    print(f"Deleted {len(plan_ids)} existing accrual plan(s)")

# --- Step 6: Verify prerequisites exist ---
eli_ids = exe('hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
if not eli_ids:
    print("ERROR: Employee 'Eli Lambert' not found in demo data!", file=sys.stderr)
    sys.exit(1)
print(f"Eli Lambert found (id={eli_ids[0]})")

mitchell_ids = exe('hr.employee', 'search', [[['name', '=', 'Mitchell Admin']]])
if not mitchell_ids:
    print("WARNING: Employee 'Mitchell Admin' not found (may use user ID 2)")
mitchell_emp_id = mitchell_ids[0] if mitchell_ids else None

# Verify res.users ID 2 exists (Mitchell Admin)
user_data = exe('res.users', 'search_read', [[['id', '=', 2]]], {'fields': ['name', 'login']})
if user_data:
    print(f"Mitchell Admin user found: {user_data[0]['name']} (login={user_data[0]['login']})")
else:
    print("WARNING: res.users id=2 not found")

print("Clean state achieved. Prerequisites verified.")
PYTHON_EOF

# -------------------------------------------------------
# Launch browser to Time Off dashboard
# -------------------------------------------------------
ensure_firefox "http://localhost:8069/web#action=hr_holidays.action_hr_holidays_dashboard"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
