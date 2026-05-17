#!/bin/bash
echo "=== Exporting employee_departure_management results ==="
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/departure_mgmt_end.png

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
    with open('/tmp/departure_mgmt_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kw=None):
    try: return models.execute_kw(db, uid, pwd, model, method, args, kw or {})
    except Exception as e: print(f"WARN {model}.{method}: {e}", file=sys.stderr); return None

def id_of(v): return v[0] if isinstance(v, (list, tuple)) and v else None

try:
    with open('/tmp/departure_mgmt_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/departure_mgmt_result.json', 'w') as f:
        json.dump({'error': f'gt_missing:{e}'}, f)
    sys.exit(0)

tina_id       = gt['tina_id']
rachel_id     = gt['rachel_id']
doris_id      = gt['doris_id']
tina_sheet_id = gt['tina_sheet_id']

# C1: Rachel and Doris no longer report to Tina
rachel_data = exe('hr.employee', 'read', [[rachel_id]], {'fields': ['parent_id']}) or [{}]
doris_data  = exe('hr.employee', 'read', [[doris_id]],  {'fields': ['parent_id']}) or [{}]
rachel_parent = id_of(rachel_data[0].get('parent_id')) if rachel_data else tina_id
doris_parent  = id_of(doris_data[0].get('parent_id'))  if doris_data  else tina_id

rachel_reassigned = (rachel_parent != tina_id)
doris_reassigned  = (doris_parent  != tina_id)

# C2: Tina's expense sheet refused
sheet_data = exe('hr.expense.sheet', 'read', [[tina_sheet_id]], {'fields': ['state']}) or [{}] \
             if tina_sheet_id else [{}]
tina_sheet_state = sheet_data[0].get('state') if sheet_data else None

# C3 & C4: Tina archived + departure reason set
tina_data = exe('hr.employee', 'search_read',
    [[['id', '=', tina_id]]],
    {'fields': ['active', 'departure_reason_id', 'departure_date'],
     'context': {'active_test': False}}) or [{}]
tina_active           = tina_data[0].get('active', True) if tina_data else True
departure_reason_id   = id_of(tina_data[0].get('departure_reason_id')) if tina_data else None
departure_date        = tina_data[0].get('departure_date') if tina_data else None

# C5: Chatter note about leave/balance posted on Tina's employee record
messages = exe('mail.message', 'search_read',
    [[['res_id', '=', tina_id],
      ['model', '=', 'hr.employee'],
      ['message_type', 'in', ['comment', 'email']]]],
    {'fields': ['body', 'date'], 'order': 'date desc', 'limit': 20}) or []
leave_note_found = any(
    any(kw in (m.get('body') or '').lower()
        for kw in ['leave', 'pto', 'paid time', 'balance', 'days remaining',
                   'vacation', 'time off'])
    for m in messages
)

result = {
    'rachel_reassigned':   rachel_reassigned,
    'doris_reassigned':    doris_reassigned,
    'rachel_parent_id':    rachel_parent,
    'doris_parent_id':     doris_parent,
    'tina_sheet_state':    tina_sheet_state,
    'tina_active':         tina_active,
    'departure_reason_id': departure_reason_id,
    'departure_date':      departure_date,
    'leave_note_found':    leave_note_found,
    'gt': {k: gt[k] for k in ['tina_id', 'rachel_id', 'doris_id', 'tina_sheet_id']},
}

with open('/tmp/departure_mgmt_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/departure_mgmt_result.json 2>/dev/null || true
echo "=== employee_departure_management export complete ==="
