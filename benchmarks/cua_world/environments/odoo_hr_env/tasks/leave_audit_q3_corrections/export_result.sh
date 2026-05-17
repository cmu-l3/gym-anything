#!/bin/bash
echo "=== Exporting leave_audit_q3_corrections results ==="
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/leave_audit_end.png

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
    with open('/tmp/leave_audit_result.json','w') as f:
        json.dump({'error':'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kw=None):
    try: return models.execute_kw(db, uid, pwd, model, method, args, kw or {})
    except Exception as e: print(f"WARN {model}.{method}: {e}", file=sys.stderr); return None

try:
    with open('/tmp/leave_audit_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/leave_audit_result.json','w') as f:
        json.dump({'error': f'gt_missing:{e}'}, f)
    sys.exit(0)

# C1: Paid Time Off validation type
pto_data = exe('hr.leave.type','read',[[gt['pto_leave_type_id']]],
               {'fields':['leave_validation_type']}) or [{}]
pto_validation = pto_data[0].get('leave_validation_type','unknown') if pto_data else 'unknown'

# C2/C3: Ernest and Ronnie leave states
def leave_state(leave_id):
    if not leave_id: return 'not_created'
    d = exe('hr.leave','read',[[leave_id]],{'fields':['state']})
    return d[0]['state'] if d else 'not_found'

ernest_leave_state = leave_state(gt.get('ernest_leave_id'))
ronnie_leave_state  = leave_state(gt.get('ronnie_leave_id'))

# C4: Eli Lambert PTO allocation
eli_allocs = []
if gt.get('pto_leave_type_id') and gt.get('eli_id'):
    eli_allocs = exe('hr.leave.allocation','search_read',[[
        ['employee_id','=',gt['eli_id']],
        ['holiday_status_id','=',gt['pto_leave_type_id']],
    ]],{'fields':['number_of_days','state','number_of_days_display']}) or []

# C5: Walter Horton allocation days
walter_alloc = {}
if gt.get('walter_alloc_id'):
    d = exe('hr.leave.allocation','read',[[gt['walter_alloc_id']]],
            {'fields':['number_of_days','state']})
    walter_alloc = d[0] if d else {}

result = {
    'pto_validation_type':  pto_validation,
    'ernest_leave_state':   ernest_leave_state,
    'ronnie_leave_state':   ronnie_leave_state,
    'eli_pto_allocations':  eli_allocs,
    'walter_alloc_days':    walter_alloc.get('number_of_days', 20),
    'walter_alloc_state':   walter_alloc.get('state', 'unknown'),
    'gt': {k: gt[k] for k in ['pto_leave_type_id','ernest_leave_id','ronnie_leave_id',
                                'eli_id','walter_id','walter_alloc_id']},
}

with open('/tmp/leave_audit_result.json','w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/leave_audit_result.json 2>/dev/null || true
echo "=== leave_audit_q3_corrections export complete ==="
