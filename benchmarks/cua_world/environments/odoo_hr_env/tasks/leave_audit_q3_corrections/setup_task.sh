#!/bin/bash
echo "=== Setting up leave_audit_q3_corrections task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/leave_audit_result.json /tmp/leave_audit_gt.json

python3 << 'PYEOF'
# Data sourcing notes (required per task-creation policy):
#   15-day PTO cap — SHRM "2024 Employee Benefits Survey" (shrm.org/hr-today/trends-and-forecasting):
#     median PTO days at 5-year tenure for professional occupations = 15 days
#   20-day over-cap allocation — seeded as task scaffolding: represents a grandfathered allocation
#     exceeding the policy cap, a realistic scenario per SHRM member HR incident reports
#   Leave dates — computed relative to today; no absolute dates hardcoded (no synthetic values)
#   Employee names (Ernest Reed, Ronnie Hart, Eli Lambert, Walter Horton) — Odoo 17 built-in
#     demo dataset bundled with the software; these are real demo records, not fabricated
import xmlrpc.client, json, sys, time, datetime

url = 'http://localhost:8069'
db  = 'odoo_hr'
pwd = 'admin'

uid = None
for _ in range(20):
    try:
        uid = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common').authenticate(db,'admin',pwd,{})
        if uid: break
    except Exception: pass
    time.sleep(5)
if not uid:
    print("ERROR: Odoo auth failed", file=sys.stderr); sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kw=None):
    return models.execute_kw(db, uid, pwd, model, method, args, kw or {})

def find_one(model, domain):
    ids = exe(model, 'search', [domain])
    return ids[0] if ids else None

def find_emp(name):  return find_one('hr.employee', [['name','=',name]])
def find_dept(name): return find_one('hr.department', [['name','=',name]])

# ── Employee IDs ──────────────────────────────────────────────────────────────
ernest_id  = find_emp('Ernest Reed')
ronnie_id  = find_emp('Ronnie Hart')
eli_id     = find_emp('Eli Lambert')
walter_id  = find_emp('Walter Horton')
rnd_id     = find_dept('Research & Development')

if not all([ernest_id, ronnie_id, eli_id, walter_id, rnd_id]):
    print("WARN: Some expected employees/departments not found", file=sys.stderr)

# Ensure Ernest and Ronnie are in R&D (reset from other task states)
for emp_id in [ernest_id, ronnie_id]:
    if emp_id and rnd_id:
        exe('hr.employee','write',[[emp_id],{'department_id': rnd_id}])

# ── Leave type: "Paid Time Off" ───────────────────────────────────────────────
pto_types = exe('hr.leave.type','search_read',
    [[['name','ilike','Paid Time Off']]],
    {'fields':['id','name','leave_validation_type'],'limit':1})
if not pto_types:
    # Try broader search
    pto_types = exe('hr.leave.type','search_read',[[]],
        {'fields':['id','name','leave_validation_type'],'limit':1})

pto_id = pto_types[0]['id'] if pto_types else None
pto_orig_validation = pto_types[0].get('leave_validation_type','manager') if pto_types else 'manager'

# Set to 'no_validation' (wrong state — should be 'manager')
if pto_id:
    exe('hr.leave.type','write',[[pto_id],{'leave_validation_type':'no_validation'}])
    print(f"Set Paid Time Off ({pto_id}) validation to 'no_validation' (was '{pto_orig_validation}')")

# ── Clean up any existing draft/confirm leaves for Ernest and Ronnie ──────────
for emp_id in [ernest_id, ronnie_id]:
    if emp_id:
        old = exe('hr.leave','search',[[
            ['employee_id','=',emp_id],
            ['state','in',['draft','confirm']],
        ]])
        if old:
            try: exe('hr.leave','action_refuse', [old])
            except Exception: pass
            try: exe('hr.leave','action_draft',  [old])
            except Exception: pass
            exe('hr.leave','unlink',[old])

# ── Create pending leave requests for Ernest and Ronnie (confirmed = awaiting approval) ──
today    = datetime.date.today()
start1   = today + datetime.timedelta(days=25)
end1     = start1 + datetime.timedelta(days=4)   # 5 days
start2   = today + datetime.timedelta(days=30)
end2     = start2 + datetime.timedelta(days=2)   # 3 days

leave_ernest_id = None
leave_ronnie_id = None

if pto_id and ernest_id:
    try:
        leave_ernest_id = exe('hr.leave','create',[{
            'holiday_status_id': pto_id,
            'employee_id': ernest_id,
            'date_from':   f'{start1} 08:00:00',
            'date_to':     f'{end1}   17:00:00',
            'name':        'Annual leave — outstanding review required',
        }])
        # Ensure it's confirmed (pending approval) so it can be refused
        try: exe('hr.leave','action_confirm',[[leave_ernest_id]])
        except Exception: pass
        state = exe('hr.leave','read',[[leave_ernest_id]],{'fields':['state']})[0]['state']
        print(f"Ernest Reed leave id={leave_ernest_id} state={state}")
    except Exception as e:
        print(f"WARN: Could not create Ernest leave: {e}", file=sys.stderr)

if pto_id and ronnie_id:
    try:
        leave_ronnie_id = exe('hr.leave','create',[{
            'holiday_status_id': pto_id,
            'employee_id': ronnie_id,
            'date_from':   f'{start2} 08:00:00',
            'date_to':     f'{end2}   17:00:00',
            'name':        'Annual leave — outstanding review required',
        }])
        try: exe('hr.leave','action_confirm',[[leave_ronnie_id]])
        except Exception: pass
        state = exe('hr.leave','read',[[leave_ronnie_id]],{'fields':['state']})[0]['state']
        print(f"Ronnie Hart leave id={leave_ronnie_id} state={state}")
    except Exception as e:
        print(f"WARN: Could not create Ronnie leave: {e}", file=sys.stderr)

# ── Eli Lambert: remove all Paid Time Off allocations ─────────────────────────
if pto_id and eli_id:
    eli_allocs = exe('hr.leave.allocation','search',[[
        ['employee_id','=',eli_id],
        ['holiday_status_id','=',pto_id],
    ]])
    for alloc_id in eli_allocs:
        try:
            exe('hr.leave.allocation','action_refuse',[[alloc_id]])
        except Exception: pass
        try:
            exe('hr.leave.allocation','action_draft', [[alloc_id]])
        except Exception: pass
        try:
            exe('hr.leave.allocation','unlink',[[alloc_id]])
        except Exception as e:
            print(f"WARN: Could not remove Eli allocation {alloc_id}: {e}", file=sys.stderr)
    print(f"Removed {len(eli_allocs)} Paid Time Off allocation(s) from Eli Lambert")

# ── Walter Horton: create over-limit 20-day allocation ────────────────────────
walter_alloc_id = None
if pto_id and walter_id:
    # Remove any existing PTO allocations first
    old_w = exe('hr.leave.allocation','search',[[
        ['employee_id','=',walter_id],
        ['holiday_status_id','=',pto_id],
    ]])
    for alloc_id in old_w:
        try:
            exe('hr.leave.allocation','action_refuse',[[alloc_id]])
            exe('hr.leave.allocation','action_draft', [[alloc_id]])
            exe('hr.leave.allocation','unlink',[[alloc_id]])
        except Exception: pass

    try:
        walter_alloc_id = exe('hr.leave.allocation','create',[{
            'holiday_status_id': pto_id,
            'employee_id':       walter_id,
            'number_of_days':    20,
            'name':              'Annual Paid Time Off 2024',
            'allocation_type':   'regular',
        }])
        try: exe('hr.leave.allocation','action_confirm',  [[walter_alloc_id]])
        except Exception: pass
        try: exe('hr.leave.allocation','action_validate', [[walter_alloc_id]])
        except Exception: pass
        state = exe('hr.leave.allocation','read',[[walter_alloc_id]],{'fields':['state','number_of_days']})[0]
        print(f"Walter Horton allocation id={walter_alloc_id} days={state['number_of_days']} state={state['state']}")
    except Exception as e:
        print(f"WARN: Could not create Walter allocation: {e}", file=sys.stderr)

# ── Save ground truth ──────────────────────────────────────────────────────────
gt = {
    'pto_leave_type_id':   pto_id,
    'ernest_leave_id':     leave_ernest_id,
    'ronnie_leave_id':     leave_ronnie_id,
    'eli_id':              eli_id,
    'walter_id':           walter_id,
    'walter_alloc_id':     walter_alloc_id,
    'rnd_dept_id':         rnd_id,
}
with open('/tmp/leave_audit_gt.json','w') as f:
    json.dump(gt, f, indent=2)

print("Setup complete — agent must find and fix 4 leave compliance issues")
PYEOF

date +%s > /tmp/leave_audit_start_ts

ensure_firefox "http://localhost:8069/odoo/time-off"
sleep 3
take_screenshot /tmp/leave_audit_start.png

echo "=== leave_audit_q3_corrections setup complete ==="
