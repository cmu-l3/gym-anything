#!/bin/bash
echo "=== Exporting restructure_division_merger results ==="
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/restructure_merger_end.png

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
    with open('/tmp/restructure_merger_result.json','w') as f:
        json.dump({'error':'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kw=None):
    try: return models.execute_kw(db, uid, pwd, model, method, args, kw or {})
    except Exception as e: print(f"WARN {model}.{method}: {e}", file=sys.stderr); return None

def id_of(v):   return v[0] if isinstance(v,(list,tuple)) and v else None
def name_of(v): return v[1] if isinstance(v,(list,tuple)) and len(v)>1 else None

try:
    with open('/tmp/restructure_merger_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/restructure_merger_result.json','w') as f:
        json.dump({'error': f'gt_missing:{e}'}, f)
    sys.exit(0)

def read_emp(emp_id):
    if not emp_id: return {}
    d = exe('hr.employee','read',[[emp_id]],{'fields':['name','department_id','job_id','parent_id','coach_id']})
    if not d: return {}
    e = d[0]
    return {
        'dept_id':   id_of(e.get('department_id')),
        'dept_name': name_of(e.get('department_id')),
        'job_id':    id_of(e.get('job_id')),
        'job_name':  name_of(e.get('job_id')),
        'mgr_id':    id_of(e.get('parent_id')),
        'coach_id':  id_of(e.get('coach_id')),
    }

ernest  = read_emp(gt['ernest_id'])
paul    = read_emp(gt['paul_id'])
randall = read_emp(gt['randall_id'])

# R&D dept: manager
rnd_data = exe('hr.department','read',[[gt['rnd_dept_id']]],{'fields':['name','manager_id','active']})
rnd = rnd_data[0] if rnd_data else {}

# LTP dept: active?  (search with active_test=False to find archived)
ltp_data = exe('hr.department','search_read',
    [[['id','=',gt['ltp_dept_id']]]],
    {'fields':['name','active'], 'context':{'active_test':False}})
ltp = ltp_data[0] if ltp_data else {}

result = {
    'ernest':  ernest,
    'paul':    paul,
    'randall': randall,
    'rnd_dept_manager_id':   id_of(rnd.get('manager_id')),
    'rnd_dept_manager_name': name_of(rnd.get('manager_id')),
    'ltp_active': ltp.get('active', True),
    'gt': {k: gt[k] for k in ['rnd_dept_id','ltp_dept_id','ernest_id','paul_id','randall_id',
                                'ronnie_id','senior_dev_id','developer_id','project_lead_id']},
}

with open('/tmp/restructure_merger_result.json','w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/restructure_merger_result.json 2>/dev/null || true
echo "=== restructure_division_merger export complete ==="
