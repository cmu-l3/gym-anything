#!/bin/bash
echo "=== Exporting expense_monthly_audit_june results ==="
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/expense_audit_end.png

python3 << 'PYEOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db  = 'odoo_hr'
pwd = 'admin'

uid = None
for _ in range(10):
    try:
        uid = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common').authenticate(db,'admin',pwd,{})
        if uid: break
    except Exception: pass
    time.sleep(3)
if not uid:
    with open('/tmp/expense_audit_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kw=None):
    try: return models.execute_kw(db, uid, pwd, model, method, args, kw or {})
    except Exception as e: print(f"WARN {model}.{method}: {e}", file=sys.stderr); return None

try:
    with open('/tmp/expense_audit_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/expense_audit_result.json', 'w') as f:
        json.dump({'error': f'gt_missing:{e}'}, f)
    sys.exit(0)

# C1: Conference Registration — can_be_expensed?
conf_data = exe('product.product', 'read',
    [[gt['conf_reg_product_id']]], {'fields': ['can_be_expensed', 'name']}) or [{}]
conf_can_be_expensed = conf_data[0].get('can_be_expensed', False) if conf_data else False

# C2: Eli Lambert expense sheet state
eli_data = exe('hr.expense.sheet', 'read',
    [[gt['eli_sheet_id']]], {'fields': ['state', 'name']}) or [{}]
eli_state = eli_data[0].get('state') if eli_data else None

# C3: Rachel Perry expense sheet state
rachel_data = exe('hr.expense.sheet', 'read',
    [[gt['rachel_sheet_id']]], {'fields': ['state', 'name']}) or [{}]
rachel_state = rachel_data[0].get('state') if rachel_data else None

# C4: Marc Demo expense sheet state
marc_data = exe('hr.expense.sheet', 'read',
    [[gt['marc_sheet_id']]], {'fields': ['state', 'name']}) or [{}]
marc_state = marc_data[0].get('state') if marc_data else None

result = {
    'conf_can_be_expensed': conf_can_be_expensed,
    'eli_sheet_state':      eli_state,
    'rachel_sheet_state':   rachel_state,
    'marc_sheet_state':     marc_state,
    'gt': {k: gt[k] for k in ['conf_reg_product_id', 'eli_sheet_id',
                                'rachel_sheet_id', 'marc_sheet_id']},
}

with open('/tmp/expense_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/expense_audit_result.json 2>/dev/null || true
echo "=== expense_monthly_audit_june export complete ==="
