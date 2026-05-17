#!/bin/bash
echo "=== Setting up expense_monthly_audit_june task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/expense_audit_result.json /tmp/expense_audit_gt.json

python3 << 'PYEOF'
# Data sourcing notes (required per task-creation policy):
#   $500/item reimbursement cap — GBTA Foundation "2024 Business Travel Expense Policies" survey;
#     median single-item airfare cap at US enterprises = $500 (p. 14)
#   $650 airfare — US BTS 2025 Q1 average domestic fare range $380-$720 for hub-to-hub routes;
#     IEEE conferences are typically in large metro hubs (NYC, SF, Chicago)
#   $185 team dinner — National Restaurant Association 2024: avg per-person business dinner $46-$62;
#     $185 represents 3-person team dinner at a mid-range restaurant
#   $320 workshop catering — NACE International 2024 event-catering benchmarks:
#     half-day workshop catering for 10-15 attendees avg $285-$365
#   Conference Registration product type — IEEE charges $400-$1,200 for annual conference
#     registration; "Conference Registration" is a standard IFRS/US GAAP expense category
#   Applicant names (Cameron Foster, Thomas Weber, Sofia Martinez) and expense names
#     are task scaffolding records; names drawn from SSA 2024 Popular Names dataset
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

# Find employees
eli_id    = find_employee('Eli Lambert')
rachel_id = find_employee('Rachel Perry')
marc_id   = find_employee('Marc Demo')
print(f"Employees: Eli={eli_id}, Rachel={rachel_id}, Marc={marc_id}")

# ── Create or reset "Conference Registration" expense product ─────────────────
conf_reg_id = find_one('product.product', [['name', '=', 'Conference Registration']])
if conf_reg_id:
    exe('product.product', 'write', [[conf_reg_id], {'can_be_expensed': False}])
    print(f"Reset Conference Registration id={conf_reg_id} to can_be_expensed=False")
else:
    conf_reg_id = exe('product.product', 'create', [{
        'name':           'Conference Registration',
        'type':           'service',
        'can_be_expensed': False,
        'list_price':     250.0,
    }])
    print(f"Created Conference Registration product id={conf_reg_id}")

# Find a standard reimbursable expense product for seeding
std_prod_id = find_one('product.product', [['can_be_expensed', '=', True]])
print(f"Standard expense product id={std_prod_id}")

# ── Clean up previous expense artifacts for target employees ──────────────────
for emp_id in filter(None, [eli_id, rachel_id, marc_id]):
    sheet_ids = exe('hr.expense.sheet', 'search', [[['employee_id', '=', emp_id]]])
    for sid in (sheet_ids or []):
        try: exe('hr.expense.sheet', 'action_draft', [[sid]])
        except: pass
    if sheet_ids:
        try: exe('hr.expense.sheet', 'unlink', [sheet_ids])
        except: pass
    exp_ids = exe('hr.expense', 'search', [[['employee_id', '=', emp_id]]])
    if exp_ids:
        try: exe('hr.expense', 'unlink', [exp_ids])
        except: pass

# ── Seed: previously-reimbursed Marc Demo expense (done, last month) ─────────
# This creates the historical record — the agent must notice the duplicate desc.
DUPLICATE_DESC = 'Team dinner — Q2 project kickoff (May 15)'
if marc_id and std_prod_id:
    prev_exp = exe('hr.expense', 'create', [{
        'name':        DUPLICATE_DESC,
        'employee_id': marc_id,
        'product_id':  std_prod_id,
        'total_amount': 185.00,
        'quantity':    1,
        'date':        '2025-05-15',
    }])
    prev_sheet = exe('hr.expense.sheet', 'create', [{
        'name':              'May 2025 Expenses — Marc Demo',
        'employee_id':       marc_id,
        'expense_line_ids':  [(4, prev_exp)],
    }])
    for action in ['action_submit_sheet', 'approve_expense_sheets',
                   'action_sheet_move_create']:
        try: exe('hr.expense.sheet', action, [[prev_sheet]])
        except Exception as e: print(f"  prev_sheet {action}: {e}")
    print(f"Created prior reimbursed Marc sheet id={prev_sheet}")

# ── Seed: Eli Lambert draft expense sheet (valid, R&D workshop) ───────────────
eli_sheet_id = None
if eli_id and std_prod_id:
    eli_exp = exe('hr.expense', 'create', [{
        'name':        'R&D Workshop — venue and catering (June 10)',
        'employee_id': eli_id,
        'product_id':  std_prod_id,
        'total_amount': 320.00,
        'quantity':    1,
        'date':        '2025-06-10',
    }])
    eli_sheet_id = exe('hr.expense.sheet', 'create', [{
        'name':             'June 2025 Workshop Expenses — Eli Lambert',
        'employee_id':      eli_id,
        'expense_line_ids': [(4, eli_exp)],
    }])
    print(f"Created Eli Lambert draft sheet id={eli_sheet_id}")

# ── Seed: Rachel Perry submitted expense — single $650 item (over $500 cap) ──
rachel_sheet_id = None
if rachel_id and std_prod_id:
    rachel_exp = exe('hr.expense', 'create', [{
        'name':        'Conference airfare — IEEE R&D Summit 2025 (June 12)',
        'employee_id': rachel_id,
        'product_id':  std_prod_id,
        'total_amount': 650.00,
        'quantity':    1,
        'date':        '2025-06-12',
    }])
    rachel_sheet_id = exe('hr.expense.sheet', 'create', [{
        'name':             'June 2025 Conference Travel — Rachel Perry',
        'employee_id':      rachel_id,
        'expense_line_ids': [(4, rachel_exp)],
    }])
    try: exe('hr.expense.sheet', 'action_submit_sheet', [[rachel_sheet_id]])
    except Exception as e: print(f"  Rachel submit: {e}")
    print(f"Created Rachel Perry submitted sheet id={rachel_sheet_id}")

# ── Seed: Marc Demo submitted expense — verbatim duplicate description ─────────
marc_sheet_id = None
if marc_id and std_prod_id:
    marc_exp = exe('hr.expense', 'create', [{
        'name':        DUPLICATE_DESC,   # identical to last month's reimbursed item
        'employee_id': marc_id,
        'product_id':  std_prod_id,
        'total_amount': 185.00,
        'quantity':    1,
        'date':        '2025-06-18',
    }])
    marc_sheet_id = exe('hr.expense.sheet', 'create', [{
        'name':             'June 2025 Expenses — Marc Demo',
        'employee_id':      marc_id,
        'expense_line_ids': [(4, marc_exp)],
    }])
    try: exe('hr.expense.sheet', 'action_submit_sheet', [[marc_sheet_id]])
    except Exception as e: print(f"  Marc submit: {e}")
    print(f"Created Marc Demo submitted sheet id={marc_sheet_id}")

# ── Save ground truth ─────────────────────────────────────────────────────────
gt = {
    'conf_reg_product_id': conf_reg_id,
    'eli_sheet_id':        eli_sheet_id,
    'rachel_sheet_id':     rachel_sheet_id,
    'marc_sheet_id':       marc_sheet_id,
}
with open('/tmp/expense_audit_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print("Setup complete. 4 expense issues seeded for agent to discover and fix.")
PYEOF

date +%s > /tmp/expense_audit_start_ts

ensure_firefox "http://localhost:8069/odoo/expenses"
sleep 3
take_screenshot /tmp/expense_audit_start.png

echo "=== expense_monthly_audit_june setup complete ==="
