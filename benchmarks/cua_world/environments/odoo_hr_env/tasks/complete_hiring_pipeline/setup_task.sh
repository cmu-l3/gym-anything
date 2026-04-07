#!/bin/bash
echo "=== Setting up complete_hiring_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Clean stale outputs BEFORE recording timestamp
rm -f /tmp/hiring_pipeline_result.json
rm -f /tmp/hiring_pipeline_gt.json

# -----------------------------------------------------------------------
# XML-RPC Setup: Ensure clean slate and all prerequisites exist
# 1. Delete any existing "Senior Data Engineer" job position + its applications
# 2. Delete any "Michael Zhang" employee, applicant, user, leave allocations
# 3. Ensure prerequisite data: departments, employees, skill types, leave types,
#    recruitment stages, work schedule, work location
# -----------------------------------------------------------------------
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, time

url = 'http://localhost:8069'
db = 'odoo_hr'
user = 'admin'
pwd = 'admin'

uid = None
for attempt in range(20):
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, user, pwd, {})
        if uid:
            break
    except Exception:
        pass
    time.sleep(5)

if not uid:
    print("ERROR: Could not authenticate to Odoo", file=sys.stderr)
    sys.exit(1)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kwargs=None):
    return models.execute_kw(db, uid, pwd, model, method, args, kwargs or {})

# ===================================================================
# CLEANUP: Remove any pre-existing task artifacts
# ===================================================================

# 1. Delete any "Michael Zhang" user
mz_user_ids = exe('res.users', 'search', [['|', ['login', '=', 'michael.zhang@dataeng.io'], ['name', 'ilike', 'Michael Zhang']]])
if mz_user_ids:
    # Unlink from employees first
    for uid_to_del in mz_user_ids:
        emp_ids = exe('hr.employee', 'search', [[['user_id', '=', uid_to_del]]])
        if emp_ids:
            exe('hr.employee', 'write', [emp_ids, {'user_id': False}])
    try:
        exe('res.users', 'unlink', [mz_user_ids])
        print(f"Deleted {len(mz_user_ids)} existing user(s) for Michael Zhang")
    except Exception as e:
        # Deactivate and rename if delete fails
        for i, u in enumerate(mz_user_ids):
            exe('res.users', 'write', [[u], {
                'active': False,
                'login': f'michael.zhang.archived.{i}@dataeng.io',
                'name': f'Michael Zhang (Archived {i})'
            }])
        print(f"Deactivated {len(mz_user_ids)} user(s): {e}")

# 2. Delete any leave allocations for Michael Zhang
mz_emp_ids = exe('hr.employee', 'search', [[['name', 'ilike', 'Michael Zhang']]])
if mz_emp_ids:
    alloc_ids = exe('hr.leave.allocation', 'search', [[['employee_id', 'in', mz_emp_ids]]])
    if alloc_ids:
        # Reset to draft before deleting (validated allocations can't be deleted directly)
        try:
            exe('hr.leave.allocation', 'action_draft', [alloc_ids])
        except Exception:
            pass
        try:
            exe('hr.leave.allocation', 'unlink', [alloc_ids])
            print(f"Deleted {len(alloc_ids)} leave allocation(s)")
        except Exception as e:
            print(f"Warning: Could not delete allocations: {e}")

# 3. Delete any "Michael Zhang" employee
if mz_emp_ids:
    # Also clean skills and resume lines
    for emp_id in mz_emp_ids:
        skill_ids = exe('hr.employee.skill', 'search', [[['employee_id', '=', emp_id]]])
        if skill_ids:
            exe('hr.employee.skill', 'unlink', [skill_ids])
        resume_ids = exe('hr.resume.line', 'search', [[['employee_id', '=', emp_id]]])
        if resume_ids:
            exe('hr.resume.line', 'unlink', [resume_ids])
    exe('hr.employee', 'unlink', [mz_emp_ids])
    print(f"Deleted {len(mz_emp_ids)} employee record(s) for Michael Zhang")

# 4. Delete any "Michael Zhang" applicant
mz_app_ids = exe('hr.applicant', 'search', [['|', ['partner_name', 'ilike', 'Michael Zhang'], ['name', 'ilike', 'Michael Zhang']]])
if mz_app_ids:
    exe('hr.applicant', 'unlink', [mz_app_ids])
    print(f"Deleted {len(mz_app_ids)} applicant(s) for Michael Zhang")

# 5. Delete any "Senior Data Engineer" job position
sde_job_ids = exe('hr.job', 'search', [[['name', '=', 'Senior Data Engineer']]])
if sde_job_ids:
    # Delete applicants linked to this job first
    linked_app_ids = exe('hr.applicant', 'search', [[['job_id', 'in', sde_job_ids]]])
    if linked_app_ids:
        exe('hr.applicant', 'unlink', [linked_app_ids])
    exe('hr.job', 'unlink', [sde_job_ids])
    print(f"Deleted 'Senior Data Engineer' job position(s)")

# ===================================================================
# PREREQUISITES: Ensure all referenced data exists
# ===================================================================

# --- Departments ---
rnd_ids = exe('hr.department', 'search', [[['name', '=', 'Research & Development']]])
if not rnd_ids:
    rnd_id = exe('hr.department', 'create', [{'name': 'Research & Development'}])
    print(f"Created 'Research & Development' dept (id={rnd_id})")
else:
    rnd_id = rnd_ids[0]
    print(f"Found 'Research & Development' dept (id={rnd_id})")

# --- Key Employees ---
marc_ids = exe('hr.employee', 'search', [[['name', '=', 'Marc Demo']]])
if not marc_ids:
    marc_id = exe('hr.employee', 'create', [{'name': 'Marc Demo', 'department_id': rnd_id}])
    print(f"Created 'Marc Demo' (id={marc_id})")
else:
    marc_id = marc_ids[0]
    print(f"Found 'Marc Demo' (id={marc_id})")

tina_ids = exe('hr.employee', 'search', [[['name', '=', 'Tina Williamson']]])
if not tina_ids:
    tina_id = exe('hr.employee', 'create', [{'name': 'Tina Williamson', 'department_id': rnd_id}])
    print(f"Created 'Tina Williamson' (id={tina_id})")
else:
    tina_id = tina_ids[0]
    print(f"Found 'Tina Williamson' (id={tina_id})")

# --- Work Schedule ---
schedule_ids = exe('resource.calendar', 'search', [[['name', 'ilike', 'Standard 40']]])
if not schedule_ids:
    # Create a standard 40h schedule if not present
    schedule_id = exe('resource.calendar', 'create', [{'name': 'Standard 40 hours/week'}])
    print(f"Created 'Standard 40 hours/week' schedule (id={schedule_id})")
else:
    schedule_id = schedule_ids[0]
    schedule_data = exe('resource.calendar', 'read', [[schedule_id]], {'fields': ['name']})
    print(f"Found work schedule: '{schedule_data[0]['name']}' (id={schedule_id})")

# --- Work Location: Home ---
try:
    home_loc_ids = exe('hr.work.location', 'search', [[['name', '=', 'Home']]])
    if not home_loc_ids:
        exe('hr.work.location', 'create', [{'name': 'Home'}])
        print("Created 'Home' work location")
    else:
        print(f"Found 'Home' work location (id={home_loc_ids[0]})")
except Exception as e:
    # hr.work.location may not exist in all Odoo 17 versions
    print(f"Work location model not available (expected in newer Odoo 17): {e}")

# --- Paid Time Off leave type ---
pto_ids = exe('hr.leave.type', 'search', [[['name', 'ilike', 'Paid Time Off']]])
if not pto_ids:
    pto_id = exe('hr.leave.type', 'create', [{
        'name': 'Paid Time Off',
        'requires_allocation': 'yes',
    }])
    print(f"Created 'Paid Time Off' leave type (id={pto_id})")
else:
    pto_id = pto_ids[0]
    print(f"Found 'Paid Time Off' leave type (id={pto_id})")

# --- Recruitment Stages ---
for stage_name in ['New', 'First Interview', 'Second Interview', 'Contract Signed']:
    stage_ids = exe('hr.recruitment.stage', 'search', [[['name', '=', stage_name]]])
    if not stage_ids:
        exe('hr.recruitment.stage', 'create', [{'name': stage_name}])
        print(f"Created recruitment stage '{stage_name}'")
    else:
        print(f"Found recruitment stage '{stage_name}' (id={stage_ids[0]})")

# --- Install hr_skills module if not installed ---
module_id = exe('ir.module.module', 'search', [[['name', '=', 'hr_skills']]])
if module_id:
    module_data = exe('ir.module.module', 'read', [module_id], {'fields': ['state']})
    if module_data and module_data[0]['state'] != 'installed':
        print("Installing hr_skills module...")
        exe('ir.module.module', 'button_immediate_install', [module_id])
        print("hr_skills installed.")
    else:
        print("hr_skills already installed")

# --- Skill Types and Skills ---
# IT skill type with Python skill
it_type_ids = exe('hr.skill.type', 'search', [[['name', '=', 'IT']]])
if not it_type_ids:
    it_type_id = exe('hr.skill.type', 'create', [{'name': 'IT'}])
    for name, progress in [('Beginner', 25), ('Intermediate', 50), ('Advanced', 75), ('Expert', 100)]:
        exe('hr.skill.level', 'create', [{'name': name, 'skill_type_id': it_type_id, 'level_progress': progress}])
    exe('hr.skill', 'create', [{'name': 'Python', 'skill_type_id': it_type_id}])
    print(f"Created IT skill type with Python skill")
else:
    it_type_id = it_type_ids[0]
    python_ids = exe('hr.skill', 'search', [[['name', '=', 'Python'], ['skill_type_id', '=', it_type_id]]])
    if not python_ids:
        exe('hr.skill', 'create', [{'name': 'Python', 'skill_type_id': it_type_id}])
    print(f"Found IT skill type (id={it_type_id})")

# Languages skill type with English skill
lang_type_ids = exe('hr.skill.type', 'search', [[['name', '=', 'Languages']]])
if not lang_type_ids:
    lang_type_id = exe('hr.skill.type', 'create', [{'name': 'Languages'}])
    for name, progress in [('Beginner', 25), ('Intermediate', 50), ('Advanced', 75), ('Expert', 100)]:
        exe('hr.skill.level', 'create', [{'name': name, 'skill_type_id': lang_type_id, 'level_progress': progress}])
    exe('hr.skill', 'create', [{'name': 'English', 'skill_type_id': lang_type_id}])
    print(f"Created Languages skill type with English skill")
else:
    lang_type_id = lang_type_ids[0]
    eng_ids = exe('hr.skill', 'search', [[['name', '=', 'English'], ['skill_type_id', '=', lang_type_id]]])
    if not eng_ids:
        exe('hr.skill', 'create', [{'name': 'English', 'skill_type_id': lang_type_id}])
    print(f"Found Languages skill type (id={lang_type_id})")

# --- Resume Line Type: Experience ---
exp_type_ids = exe('hr.resume.line.type', 'search', [[['name', '=', 'Experience']]])
if not exp_type_ids:
    exe('hr.resume.line.type', 'create', [{'name': 'Experience', 'sequence': 1}])
    print("Created 'Experience' resume line type")
else:
    print(f"Found 'Experience' resume line type (id={exp_type_ids[0]})")

# --- Install hr_recruitment module if not installed ---
recruit_mod = exe('ir.module.module', 'search', [[['name', '=', 'hr_recruitment']]])
if recruit_mod:
    mod_data = exe('ir.module.module', 'read', [recruit_mod], {'fields': ['state']})
    if mod_data and mod_data[0]['state'] != 'installed':
        print("Installing hr_recruitment module...")
        exe('ir.module.module', 'button_immediate_install', [recruit_mod])
        print("hr_recruitment installed.")
    else:
        print("hr_recruitment already installed")

# --- Install hr_holidays (Time Off) module if not installed ---
holidays_mod = exe('ir.module.module', 'search', [[['name', '=', 'hr_holidays']]])
if holidays_mod:
    mod_data = exe('ir.module.module', 'read', [holidays_mod], {'fields': ['state']})
    if mod_data and mod_data[0]['state'] != 'installed':
        print("Installing hr_holidays module...")
        exe('ir.module.module', 'button_immediate_install', [holidays_mod])
        print("hr_holidays installed.")
    else:
        print("hr_holidays already installed")

# ===================================================================
# Save ground truth for export/verifier
# ===================================================================
gt = {
    'rnd_dept_id': rnd_id,
    'marc_demo_id': marc_id,
    'tina_williamson_id': tina_id,
    'schedule_id': schedule_id,
    'pto_leave_type_id': pto_id,
}
with open('/tmp/hiring_pipeline_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print("\n=== Setup complete ===")
print("  Agent must: create job position -> start recruitment -> create application")
print("  -> advance stages -> create employee -> configure profile -> allocate PTO")
print("  -> stop recruitment")
PYTHON_EOF

# Record timestamp AFTER cleanup, BEFORE agent starts
date +%s > /tmp/task_start_timestamp

# Launch Firefox at the Recruitment > Job Positions page
ensure_firefox "http://localhost:8069/web#action=hr_recruitment.action_hr_job_config&view_type=list"
sleep 3

take_screenshot /tmp/hiring_pipeline_start.png

echo "Task start: Agent must complete full hiring pipeline for Senior Data Engineer."
echo "=== complete_hiring_pipeline setup complete ==="
