#!/bin/bash
echo "=== Exporting recruitment_q2_pipeline_cleanup results ==="
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/recruitment_cleanup_end.png

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
    with open('/tmp/recruitment_cleanup_result.json','w') as f:
        json.dump({'error':'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kw=None):
    try: return models.execute_kw(db, uid, pwd, model, method, args, kw or {})
    except Exception as e: print(f"WARN {model}.{method}: {e}", file=sys.stderr); return None

def id_of(v): return v[0] if isinstance(v,(list,tuple)) and v else None

try:
    with open('/tmp/recruitment_cleanup_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/recruitment_cleanup_result.json','w') as f:
        json.dump({'error': f'gt_missing:{e}'}, f)
    sys.exit(0)

# C1: Technical Assessment stage sequence
ta_data = exe('hr.recruitment.stage','read',[[gt['tech_assess_stage_id']]],
              {'fields':['sequence']}) or [{}]
ta_seq = ta_data[0].get('sequence') if ta_data else None

# Reference sequences for First and Second Interview
first_data  = exe('hr.recruitment.stage','read',[[gt['first_interview_stage_id']]],
                  {'fields':['sequence']}) if gt.get('first_interview_stage_id') else [{}]
second_data = exe('hr.recruitment.stage','read',[[gt['second_interview_stage_id']]],
                  {'fields':['sequence']}) if gt.get('second_interview_stage_id') else [{}]
first_seq  = first_data[0].get('sequence',  gt['first_interview_seq'])  if first_data  else gt['first_interview_seq']
second_seq = second_data[0].get('sequence', gt['second_interview_seq']) if second_data else gt['second_interview_seq']

# C2: Cameron Foster archived?
cameron_data = exe('hr.applicant','search_read',
    [[['id','=',gt['cameron_foster_id']]]],
    {'fields':['active','stage_id'],'context':{'active_test':False}}) or []
cameron_active = cameron_data[0]['active'] if cameron_data else True

# C3: Thomas Weber — SDS one archived, ExpDev one active
thomas_sds_data    = exe('hr.applicant','search_read',
    [[['id','=',gt['thomas_weber_sds_id']]]],
    {'fields':['active','stage_id'],'context':{'active_test':False}}) or []
thomas_expdev_data = exe('hr.applicant','search_read',
    [[['id','=',gt['thomas_weber_expdev_id']]]],
    {'fields':['active','stage_id'],'context':{'active_test':False}}) or []

thomas_sds_active    = thomas_sds_data[0]['active']    if thomas_sds_data    else True
thomas_expdev_active = thomas_expdev_data[0]['active'] if thomas_expdev_data else True

# C4: Sofia Martinez — hired (emp_id set) and/or in Contract Signed stage
sofia_data = exe('hr.applicant','search_read',
    [[['id','=',gt['sofia_martinez_id']]]],
    {'fields':['active','stage_id','emp_id'],'context':{'active_test':False}}) or []
sofia_emp_id  = id_of(sofia_data[0].get('emp_id'))  if sofia_data else None
sofia_stage_id = id_of(sofia_data[0].get('stage_id')) if sofia_data else None

# Find "Contract Signed" stage id for comparison
cs_ids = exe('hr.recruitment.stage','search',[[['name','ilike','Contract Signed']]])
contract_signed_id = cs_ids[0] if cs_ids else None

sofia_hired      = bool(sofia_emp_id)
sofia_at_cs      = sofia_stage_id == contract_signed_id

result = {
    'ta_sequence':          ta_seq,
    'first_interview_seq':  first_seq,
    'second_interview_seq': second_seq,
    'cameron_active':       cameron_active,
    'thomas_sds_active':    thomas_sds_active,
    'thomas_expdev_active': thomas_expdev_active,
    'sofia_hired':          sofia_hired,
    'sofia_at_contract_signed': sofia_at_cs,
    'sofia_emp_id':         sofia_emp_id,
    'gt': {k: gt[k] for k in ['tech_assess_stage_id','first_interview_stage_id',
                                'second_interview_stage_id','cameron_foster_id',
                                'thomas_weber_sds_id','thomas_weber_expdev_id',
                                'sofia_martinez_id']},
}

with open('/tmp/recruitment_cleanup_result.json','w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/recruitment_cleanup_result.json 2>/dev/null || true
echo "=== recruitment_q2_pipeline_cleanup export complete ==="
