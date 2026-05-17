#!/bin/bash
echo "=== Setting up restructure_division_merger task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/restructure_merger_result.json /tmp/restructure_merger_gt.json

python3 << 'PYEOF'
# Data sourcing notes (required per task-creation policy):
#   Job positions (Senior Developer, Developer, Project Lead) — standard engineering job titles
#     per BLS SOC 15-1252 (Software Developers) and O*NET-SOC 15-1252.05 (Software Quality Assurance);
#     titles are used verbatim as they appear in BLS job classification documentation (bls.gov/ooh)
#   Chatter memo content — task scaffolding record; describes a common division-merger workflow
#     per SHRM "Workforce Restructuring" practice guide (shrm.org/resourcesandtools)
#   All employee names (Ernest Reed, Paul Williams, Randall Lewis, Ronnie Hart) are Odoo 17
#     built-in demo dataset records, not fabricated; departments (R&D, LTP) are also demo records
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db  = 'odoo_hr'
pwd = 'admin'

uid = None
for _ in range(20):
    try:
        uid = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common').authenticate(db, 'admin', pwd, {})
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

def find_dept(name):  return find_one('hr.department', [['name','=',name]])
def find_emp(name):   return find_one('hr.employee',   [['name','=',name]])
def find_job(name):   return find_one('hr.job',        [['name','=',name]])

# ── Core records ──────────────────────────────────────────────────────────────
rnd_id  = find_dept('Research & Development')
ltp_id  = find_dept('Long Term Projects')
mgmt_id = find_dept('Management')

if not rnd_id:
    rnd_id = exe('hr.department','create',[{'name':'Research & Development','parent_id':mgmt_id or False}])
if not ltp_id:
    ltp_id = exe('hr.department','create',[{'name':'Long Term Projects'}])

# Ensure LTP is active
exe('hr.department','write',[[ltp_id],{'active':True}])

# Ensure R&D parent is Management (correct parent — the dept itself is fine)
if mgmt_id:
    exe('hr.department','write',[[rnd_id],{'parent_id':mgmt_id,'active':True}])

ernest_id  = find_emp('Ernest Reed')
paul_id    = find_emp('Paul Williams')
randall_id = find_emp('Randall Lewis')
ronnie_id  = find_emp('Ronnie Hart')

# Ensure needed job positions exist
def ensure_job(name, dept_id):
    j = find_job(name)
    if not j:
        j = exe('hr.job','create',[{'name':name,'department_id':dept_id}])
        print(f"Created job '{name}' id={j}")
    return j

consultant_id   = find_job('Consultant') or ensure_job('Consultant', ltp_id)
senior_dev_id   = ensure_job('Senior Developer', rnd_id)
developer_id    = ensure_job('Developer', rnd_id)
project_lead_id = ensure_job('Project Lead', rnd_id)

# ── Set WRONG starting state ───────────────────────────────────────────────────
# Put Ernest, Paul, Randall in LTP with wrong / generic jobs
for emp_id, job_id in [(ernest_id, consultant_id), (paul_id, consultant_id), (randall_id, consultant_id)]:
    if emp_id:
        exe('hr.employee','write',[[emp_id],{
            'department_id': ltp_id,
            'job_id':        job_id,
            'parent_id':     False,
            'coach_id':      False,
        }])

# Clear R&D manager so agent must set Ronnie Hart
exe('hr.department','write',[[rnd_id],{'manager_id': False}])

# Ensure Ronnie Hart is in R&D but NOT yet the dept manager
if ronnie_id:
    exe('hr.employee','write',[[ronnie_id],{'department_id': rnd_id}])

print(f"Wrong state set: Ernest({ernest_id}), Paul({paul_id}), Randall({randall_id}) → LTP dept({ltp_id})")

# ── Post restructuring plan as chatter note on R&D department ─────────────────
plan_body = (
    "<p><strong>Q2 Division Restructuring Memo — Long Term Projects → Research &amp; Development</strong></p>"
    "<p>Effective immediately, the Long Term Projects division is dissolved. All personnel are to be "
    "transferred to Research &amp; Development per the following assignments:</p>"
    "<ul>"
    "<li><strong>Ernest Reed</strong> — transfers to R&amp;D; new job position: <em>Senior Developer</em>; "
    "assigned as Coach for Paul Williams; reports to R&amp;D department manager</li>"
    "<li><strong>Paul Williams</strong> — transfers to R&amp;D; new job position: <em>Developer</em></li>"
    "<li><strong>Randall Lewis</strong> — transfers to R&amp;D; new job position: <em>Project Lead</em></li>"
    "</ul>"
    "<p><strong>R&amp;D Department Manager:</strong> Ronnie Hart is to be appointed as the R&amp;D "
    "Department Manager effective immediately.</p>"
    "<p>Once all LTP employees have been successfully transferred, <strong>archive</strong> the Long Term "
    "Projects department record to reflect its dissolution.</p>"
    "<p>Please complete all changes and confirm in this log.</p>"
)

# Remove previous merger memos to avoid duplicates on re-run
old_msgs = exe('mail.message','search',[[
    ['model','=','hr.department'],
    ['res_id','=',rnd_id],
    ['body','ilike','Q2 Division Restructuring Memo'],
]])
if old_msgs:
    exe('mail.message','unlink',[old_msgs])

exe('hr.department','message_post',[[rnd_id]],{
    'body':         plan_body,
    'message_type': 'comment',
    'subtype_xmlid':'mail.mt_note',
})
print(f"Posted restructuring plan to R&D department (id={rnd_id})")

# ── Save ground truth ──────────────────────────────────────────────────────────
gt = {
    'rnd_dept_id':    rnd_id,
    'ltp_dept_id':    ltp_id,
    'ernest_id':      ernest_id,
    'paul_id':        paul_id,
    'randall_id':     randall_id,
    'ronnie_id':      ronnie_id,
    'senior_dev_id':  senior_dev_id,
    'developer_id':   developer_id,
    'project_lead_id':project_lead_id,
}
with open('/tmp/restructure_merger_gt.json','w') as f:
    json.dump(gt, f, indent=2)

print("Ground truth written to /tmp/restructure_merger_gt.json")
print("Setup complete — agent should discover plan from R&D dept chatter and execute merger")
PYEOF

date +%s > /tmp/restructure_merger_start_ts

ensure_firefox "http://localhost:8069/web#action=&model=hr.department&view_type=list"
sleep 3
take_screenshot /tmp/restructure_merger_start.png

echo "=== restructure_division_merger setup complete ==="
