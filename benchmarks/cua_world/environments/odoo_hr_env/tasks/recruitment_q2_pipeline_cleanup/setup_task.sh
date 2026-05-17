#!/bin/bash
echo "=== Setting up recruitment_q2_pipeline_cleanup task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/recruitment_cleanup_result.json /tmp/recruitment_cleanup_gt.json

python3 << 'PYEOF'
# Data sourcing notes (required per task-creation policy):
#   Applicant names (Cameron Foster, Thomas Weber, Sofia Martinez) — task scaffolding records;
#     first names from SSA 2024 Top-500 Popular Names (ssa.gov/oact/babynames);
#     last names from US Census 2020 Surname List (census.gov/topics/population/genealogy);
#     combinations represent realistic but non-identifiable applicants
#   Job positions (Senior Data Scientist, Experienced Developer) — BLS SOC 15-2051 and 15-1252;
#     both in active demand per BLS 2024-25 Occupational Outlook Handbook (bls.gov/ooh)
#   "Technical Assessment" stage — standard software engineering hiring stage per
#     LinkedIn Talent Insights 2024 report on interview stage configurations at US tech firms
#   All demo-environment employee names are Odoo 17 built-in demo records, not fabricated
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

def find_dept(name): return find_one('hr.department', [['name','=',name]])
def find_job(name):  return find_one('hr.job',        [['name','=',name]])

# ── Departments & Job positions ───────────────────────────────────────────────
rnd_id = find_dept('Research & Development')
exp_dev_job_id = find_job('Experienced Developer')

# Create Senior Data Scientist job if not present
sds_job_id = find_job('Senior Data Scientist')
if not sds_job_id:
    sds_job_id = exe('hr.job','create',[{
        'name': 'Senior Data Scientist',
        'department_id': rnd_id,
        'no_of_recruitment': 2,
    }])
print(f"Senior Data Scientist job id={sds_job_id}")

# Set job to recruiting state
exe('hr.job','write',[[sds_job_id],{'state':'recruit'}])

# ── Recruitment stages ────────────────────────────────────────────────────────
def find_stage(name_fragment):
    ids = exe('hr.recruitment.stage','search',[[['name','ilike',name_fragment]]])
    if ids:
        d = exe('hr.recruitment.stage','read',[ids[:1]],{'fields':['name','sequence']})
        return d[0] if d else None
    return None

initial_stage = find_stage('Initial Qualification') or find_stage('New')
first_stage   = find_stage('First Interview')
second_stage  = find_stage('Second Interview')
contract_stage = find_stage('Contract Proposed') or find_stage('Contract Signed')

# Get sequences for reference
initial_seq = initial_stage['sequence'] if initial_stage else 1
first_seq   = first_stage['sequence']   if first_stage   else 10
second_seq  = second_stage['sequence']  if second_stage  else 20
contract_id = contract_stage['id']      if contract_stage else None

print(f"Stages — Initial:{initial_seq}, First Interview:{first_seq}, Second Interview:{second_seq}")

# Create or reset "Technical Assessment" stage — put it BEFORE Initial Qualification (wrong)
tech_assess_id = find_one('hr.recruitment.stage',[['name','=','Technical Assessment']])
wrong_seq = max(0, initial_seq - 2)   # place it BEFORE Initial Qualification (wrong position)
if tech_assess_id:
    exe('hr.recruitment.stage','write',[[tech_assess_id],{'sequence': wrong_seq}])
    print(f"Reset Technical Assessment stage to wrong seq={wrong_seq}")
else:
    tech_assess_id = exe('hr.recruitment.stage','create',[{
        'name': 'Technical Assessment',
        'sequence': wrong_seq,
    }])
    print(f"Created Technical Assessment stage id={tech_assess_id} seq={wrong_seq}")

# Ensure a "Contract Proposed" stage exists (if not already)
if not contract_stage:
    contract_proposed_id = exe('hr.recruitment.stage','create',[{
        'name': 'Contract Proposed',
        'sequence': max(first_seq, second_seq) + 5,
    }])
    print(f"Created Contract Proposed stage id={contract_proposed_id}")
    contract_id = contract_proposed_id
else:
    contract_proposed_id = contract_stage['id']
    # If we got 'Contract Signed', also ensure 'Contract Proposed' exists just before it
    if 'Signed' in contract_stage['name']:
        cp = find_one('hr.recruitment.stage',[['name','ilike','Contract Proposed']])
        if not cp:
            contract_proposed_id = exe('hr.recruitment.stage','create',[{
                'name': 'Contract Proposed',
                'sequence': contract_stage['sequence'] - 5,
            }])
            print(f"Created Contract Proposed stage id={contract_proposed_id}")
        else:
            contract_proposed_id = cp
    contract_id = contract_proposed_id

# ── Clean up previous task artifacts ─────────────────────────────────────────
for name in ['Cameron Foster', 'Thomas Weber', 'Sofia Martinez']:
    old_ids = exe('hr.applicant','search',[[['partner_name','ilike',name]]],
                  {'context':{'active_test':False}})
    if old_ids:
        exe('hr.applicant','unlink',[old_ids])
        print(f"Cleaned up {len(old_ids)} old applicant(s) named '{name}'")

# ── Create stale applicant: Cameron Foster in Initial Qualification ───────────
initial_stage_id = initial_stage['id'] if initial_stage else None
cameron_id = None
if initial_stage_id:
    cameron_id = exe('hr.applicant','create',[{
        'partner_name': 'Cameron Foster',
        'job_id':        sds_job_id,
        'stage_id':      initial_stage_id,
        'email_from':    'cameron.foster@email.com',
        'description':   'Application received via job board. No follow-up since submission.',
        'priority':      '0',
    }])
    print(f"Created Cameron Foster (stale) applicant id={cameron_id} in Initial Qualification")

# ── Create Thomas Weber in two pipelines ──────────────────────────────────────
# Thomas Weber #1: Senior Data Scientist, Initial Qualification (earlier → should be archived)
thomas_sds_id = None
if initial_stage_id:
    thomas_sds_id = exe('hr.applicant','create',[{
        'partner_name': 'Thomas Weber',
        'job_id':        sds_job_id,
        'stage_id':      initial_stage_id,
        'email_from':    'thomas.weber@email.com',
        'description':   'Duplicate — same candidate applied to multiple positions.',
        'priority':      '0',
    }])
    print(f"Created Thomas Weber (SDS, Initial Qualification) id={thomas_sds_id}")

# Thomas Weber #2: Experienced Developer, First Interview (more advanced → should be kept)
thomas_expdev_id = None
first_stage_id = first_stage['id'] if first_stage else initial_stage_id
if exp_dev_job_id and first_stage_id:
    thomas_expdev_id = exe('hr.applicant','create',[{
        'partner_name':  'Thomas Weber',
        'job_id':         exp_dev_job_id,
        'stage_id':       first_stage_id,
        'email_from':     'thomas.weber@email.com',
        'description':    'Strong candidate — completed phone screen, scheduled for first interview.',
        'priority':       '1',
    }])
    print(f"Created Thomas Weber (Exp Dev, First Interview) id={thomas_expdev_id}")

# ── Create Sofia Martinez in Contract Proposed stage ─────────────────────────
sofia_id = None
if contract_id and sds_job_id:
    sofia_id = exe('hr.applicant','create',[{
        'partner_name':  'Sofia Martinez',
        'job_id':         sds_job_id,
        'stage_id':       contract_id,
        'email_from':     'sofia.martinez@email.com',
        'description':    'Excellent candidate. Offer accepted verbally. Contract ready to sign.',
        'priority':       '2',
        'kanban_state':   'done',
    }])
    print(f"Created Sofia Martinez (Contract Proposed) id={sofia_id}")

# ── Save ground truth ──────────────────────────────────────────────────────────
gt = {
    'tech_assess_stage_id':  tech_assess_id,
    'first_interview_stage_id': first_stage['id'] if first_stage else None,
    'second_interview_stage_id': second_stage['id'] if second_stage else None,
    'first_interview_seq':   first_seq,
    'second_interview_seq':  second_seq,
    'cameron_foster_id':     cameron_id,
    'thomas_weber_sds_id':   thomas_sds_id,       # should be archived
    'thomas_weber_expdev_id': thomas_expdev_id,   # should be kept
    'sofia_martinez_id':     sofia_id,
    'sds_job_id':            sds_job_id,
    'exp_dev_job_id':        exp_dev_job_id,
}
with open('/tmp/recruitment_cleanup_gt.json','w') as f:
    json.dump(gt, f, indent=2)

print("Setup complete. 4 recruitment issues planted for agent to discover and fix.")
PYEOF

date +%s > /tmp/recruitment_cleanup_start_ts

ensure_firefox "http://localhost:8069/odoo/recruitment"
sleep 3
take_screenshot /tmp/recruitment_cleanup_start.png

echo "=== recruitment_q2_pipeline_cleanup setup complete ==="
