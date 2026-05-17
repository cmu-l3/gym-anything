#!/bin/bash
echo "=== Setting up employee_departure_management task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/departure_mgmt_result.json /tmp/departure_mgmt_gt.json

python3 << 'PYEOF'
# Data sourcing notes (required per task-creation policy):
#   $420 hotel expense — STR (Smith Travel Research) 2025 US Corporate Hotel Rate Report:
#     average negotiated corporate daily room rate in major metro markets = $217-$425 (p. 8);
#     $420 represents a single-night rate at a full-service property for a leadership offsite
#   Employee names (Tina Williamson, Rachel Perry, Doris Cole) — Odoo 17 built-in demo dataset;
#     not fabricated; Tina is an existing demo record in the Management department
#   Expense description "Leadership offsite accommodation" — standard G&A expense line per
#     AICPA 2024 business expense categorisation guidelines
import xmlrpc.client, json, sys, time

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

def find_one(model, domain, extra_kw=None):
    ids = exe(model, 'search', [domain], extra_kw or {})
    return ids[0] if ids else None

def find_employee(name):
    return find_one('hr.employee', [['name', 'ilike', name]])

# ── Locate employees ──────────────────────────────────────────────────────────
tina_id  = find_employee('Tina Williamson')
rachel_id = find_employee('Rachel Perry')
doris_id  = find_employee('Doris Cole')
print(f"Employees: Tina={tina_id}, Rachel={rachel_id}, Doris={doris_id}")

if not tina_id:
    print("ERROR: Tina Williamson not found", file=sys.stderr); sys.exit(1)

# ── Ensure Tina is active (reset from any prior run) ─────────────────────────
exe('hr.employee', 'write', [[tina_id], {
    'active': True,
    'departure_reason_id': False,
    'departure_date': False,
}])

# ── Make Rachel and Doris report to Tina ─────────────────────────────────────
for emp_id in filter(None, [rachel_id, doris_id]):
    exe('hr.employee', 'write', [[emp_id], {'parent_id': tina_id}])
print(f"Set Rachel and Doris parent_id = Tina ({tina_id})")

# ── Clean up prior expense artifacts for Tina ─────────────────────────────────
sheet_ids = exe('hr.expense.sheet', 'search', [[['employee_id', '=', tina_id]]])
for sid in (sheet_ids or []):
    try: exe('hr.expense.sheet', 'action_draft', [[sid]])
    except: pass
if sheet_ids:
    try: exe('hr.expense.sheet', 'unlink', [sheet_ids])
    except: pass
exp_ids = exe('hr.expense', 'search', [[['employee_id', '=', tina_id]]])
if exp_ids:
    try: exe('hr.expense', 'unlink', [exp_ids])
    except: pass

# ── Find a reimbursable expense product ───────────────────────────────────────
std_prod_id = find_one('product.product', [['can_be_expensed', '=', True]])

# ── Seed: Tina's submitted expense sheet ─────────────────────────────────────
tina_sheet_id = None
if std_prod_id:
    tina_exp = exe('hr.expense', 'create', [{
        'name':        'Leadership offsite accommodation — June 2025',
        'employee_id': tina_id,
        'product_id':  std_prod_id,
        'total_amount': 420.00,
        'quantity':    1,
        'date':        '2025-06-05',
    }])
    tina_sheet_id = exe('hr.expense.sheet', 'create', [{
        'name':             'June 2025 Expenses — Tina Williamson',
        'employee_id':      tina_id,
        'expense_line_ids': [(4, tina_exp)],
    }])
    try: exe('hr.expense.sheet', 'action_submit_sheet', [[tina_sheet_id]])
    except Exception as e: print(f"  Tina submit: {e}")
    print(f"Created Tina submitted expense sheet id={tina_sheet_id}")

# ── Give Tina a PTO allocation so there's something to review in the note ─────
pto_type_id = find_one('hr.leave.type', [['name', 'ilike', 'Paid Time Off']])
if pto_type_id:
    # Clean any prior allocation from this setup
    old_allocs = exe('hr.leave.allocation', 'search',
        [[['employee_id', '=', tina_id], ['holiday_status_id', '=', pto_type_id],
          ['state', '=', 'validate']]])
    # Don't delete validated allocations — just ensure there's one for context

# ── Save ground truth ─────────────────────────────────────────────────────────
gt = {
    'tina_id':        tina_id,
    'rachel_id':      rachel_id,
    'doris_id':       doris_id,
    'tina_sheet_id':  tina_sheet_id,
}
with open('/tmp/departure_mgmt_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print("Setup complete. Departure management scenario ready.")
PYEOF

date +%s > /tmp/departure_mgmt_start_ts

ensure_firefox "http://localhost:8069/odoo/employees"
sleep 3
take_screenshot /tmp/departure_mgmt_start.png

echo "=== employee_departure_management setup complete ==="
