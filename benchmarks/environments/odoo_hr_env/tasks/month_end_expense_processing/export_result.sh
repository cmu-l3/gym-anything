#!/bin/bash
echo "=== Exporting month_end_expense_processing results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/expense_processing_end.png

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
    with open('/tmp/expense_processing_result.json', 'w') as f:
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
    with open('/tmp/expense_processing_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/expense_processing_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

# Odoo expense sheet states:
# draft -> submit -> approve -> post -> done
SUBMITTED_STATES = ['submit', 'approve', 'post', 'done']
APPROVED_STATES = ['approve', 'post', 'done']

def get_best_sheet_for_employee(emp_id):
    """Get the expense sheet with the most advanced state for an employee."""
    sheets = exe('hr.expense.sheet', 'search_read',
                 [[['employee_id', '=', emp_id]]],
                 {'fields': ['name', 'state', 'employee_id']})
    if not sheets:
        return None
    # Return the sheet with the most advanced state
    state_order = {'draft': 0, 'submit': 1, 'approve': 2, 'post': 3, 'done': 4}
    best = max(sheets, key=lambda s: state_order.get(s.get('state', 'draft'), 0))
    return best

anita_id = gt.get('anita_oliver_id')
sharlene_id = gt.get('sharlene_rhodes_id')
paul_id = gt.get('paul_williams_id')

anita_sheet = get_best_sheet_for_employee(anita_id) if anita_id else None
sharlene_sheet = get_best_sheet_for_employee(sharlene_id) if sharlene_id else None
paul_sheet = get_best_sheet_for_employee(paul_id) if paul_id else None

def sheet_info(sheet):
    if not sheet:
        return {'exists': False, 'state': None, 'name': ''}
    return {
        'exists': True,
        'state': sheet.get('state', 'draft'),
        'name': sheet.get('name', ''),
        'submitted': sheet.get('state') in SUBMITTED_STATES,
        'approved': sheet.get('state') in APPROVED_STATES,
    }

result = {
    'anita_oliver': sheet_info(anita_sheet),
    'sharlene_rhodes': sheet_info(sharlene_sheet),
    'paul_williams': sheet_info(paul_sheet),
}

with open('/tmp/expense_processing_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/expense_processing_result.json 2>/dev/null || true
echo "=== month_end_expense_processing export complete ==="
