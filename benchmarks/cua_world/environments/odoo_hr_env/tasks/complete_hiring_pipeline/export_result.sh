#!/bin/bash
echo "=== Exporting complete_hiring_pipeline results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/hiring_pipeline_end.png

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
    with open('/tmp/hiring_pipeline_result.json', 'w') as f:
        json.dump({'error': 'auth_failed'}, f)
    sys.exit(0)

models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

def exe(model, method, args, kwargs=None):
    try:
        return models.execute_kw(db, uid, pwd, model, method, args, kwargs or {})
    except Exception:
        return None

def get_id(val):
    return val[0] if isinstance(val, (list, tuple)) and len(val) >= 1 else None

def get_name(val):
    return val[1] if isinstance(val, (list, tuple)) and len(val) >= 2 else None

# Load ground truth
try:
    with open('/tmp/hiring_pipeline_gt.json') as f:
        gt = json.load(f)
except Exception as e:
    with open('/tmp/hiring_pipeline_result.json', 'w') as f:
        json.dump({'error': f'gt_missing: {e}'}, f)
    sys.exit(0)

result = {}

# ===================================================================
# 1. Check Job Position "Senior Data Engineer"
# ===================================================================
job_ids = exe('hr.job', 'search', [[['name', '=', 'Senior Data Engineer']]])
job_result = {'exists': False}
if job_ids:
    job_id = job_ids[0]
    job_data = exe('hr.job', 'read', [[job_id]],
                   {'fields': ['name', 'department_id', 'no_of_recruitment']})
    if job_data:
        j = job_data[0]
        job_result = {
            'exists': True,
            'dept_id': get_id(j.get('department_id')),
            'dept_name': get_name(j.get('department_id')),
            'in_rnd': get_id(j.get('department_id')) == gt['rnd_dept_id'],
            'no_of_recruitment': j.get('no_of_recruitment', 0),
            'recruitment_stopped': j.get('no_of_recruitment', 0) == 0,
        }
result['job_position'] = job_result

# ===================================================================
# 2. Check Applicant "Michael Zhang"
# ===================================================================
app_ids = exe('hr.applicant', 'search', [['|',
    ['partner_name', 'ilike', 'Michael Zhang'],
    ['name', 'ilike', 'Michael Zhang']
]])
app_result = {'exists': False}
if app_ids:
    app_data = exe('hr.applicant', 'read', [[app_ids[0]]],
                   {'fields': ['partner_name', 'name', 'stage_id', 'email_from',
                               'partner_phone', 'salary_expected', 'job_id', 'emp_id']})
    if app_data:
        a = app_data[0]
        stage_name = get_name(a.get('stage_id')) or ''
        app_result = {
            'exists': True,
            'partner_name': a.get('partner_name', ''),
            'stage_name': stage_name,
            'is_contract_signed': 'Contract Signed' in stage_name or 'Hired' in stage_name,
            'email': a.get('email_from', ''),
            'phone': a.get('partner_phone', ''),
            'salary_expected': a.get('salary_expected', 0),
            'job_name': get_name(a.get('job_id')),
            'linked_emp_id': get_id(a.get('emp_id')),
        }
result['applicant'] = app_result

# ===================================================================
# 3. Check Employee "Michael Zhang"
# ===================================================================
emp_ids = exe('hr.employee', 'search', [[['name', 'ilike', 'Michael Zhang']]])
emp_result = {'exists': False}
if emp_ids:
    emp_id = emp_ids[0]
    emp_data = exe('hr.employee', 'read', [[emp_id]],
                   {'fields': ['name', 'job_title', 'job_id', 'department_id', 'parent_id',
                               'coach_id', 'resource_calendar_id', 'work_location_id',
                               'barcode', 'pin',
                               'private_street', 'private_city', 'private_state_id',
                               'private_zip', 'private_country_id',
                               'user_id']})
    if emp_data:
        e = emp_data[0]
        emp_result = {
            'exists': True,
            'name': e.get('name', ''),
            'job_title': e.get('job_title', ''),
            'job_position_name': get_name(e.get('job_id')),
            'dept_id': get_id(e.get('department_id')),
            'dept_name': get_name(e.get('department_id')),
            'in_rnd': get_id(e.get('department_id')) == gt['rnd_dept_id'],
            'manager_id': get_id(e.get('parent_id')),
            'manager_name': get_name(e.get('parent_id')),
            'has_marc_manager': get_id(e.get('parent_id')) == gt['marc_demo_id'],
            'coach_id': get_id(e.get('coach_id')),
            'coach_name': get_name(e.get('coach_id')),
            'has_tina_coach': get_id(e.get('coach_id')) == gt['tina_williamson_id'],
            'schedule_id': get_id(e.get('resource_calendar_id')),
            'schedule_name': get_name(e.get('resource_calendar_id')),
            'has_standard_schedule': get_id(e.get('resource_calendar_id')) == gt['schedule_id'],
            'work_location_name': get_name(e.get('work_location_id')),
            'badge_id': e.get('barcode', ''),
            'pin': e.get('pin', ''),
            'private_street': e.get('private_street', ''),
            'private_city': e.get('private_city', ''),
            'private_state_name': get_name(e.get('private_state_id')),
            'private_zip': e.get('private_zip', ''),
            'private_country_name': get_name(e.get('private_country_id')),
            'user_id': get_id(e.get('user_id')),
            'user_name': get_name(e.get('user_id')),
        }

        # Check if employee is linked to the applicant
        if app_result.get('exists') and app_result.get('linked_emp_id'):
            emp_result['linked_to_application'] = (app_result['linked_emp_id'] == emp_id)
        else:
            emp_result['linked_to_application'] = False

        # Check skills
        skill_ids = exe('hr.employee.skill', 'search', [[['employee_id', '=', emp_id]]])
        skills_found = []
        if skill_ids:
            skills_data = exe('hr.employee.skill', 'read', [skill_ids],
                              {'fields': ['skill_id', 'skill_level_id', 'skill_type_id']})
            for s in (skills_data or []):
                skills_found.append({
                    'skill': get_name(s.get('skill_id')),
                    'level': get_name(s.get('skill_level_id')),
                    'type': get_name(s.get('skill_type_id')),
                })
        emp_result['skills'] = skills_found

        # Check resume lines
        resume_ids = exe('hr.resume.line', 'search', [[['employee_id', '=', emp_id]]])
        resume_found = []
        if resume_ids:
            resume_data = exe('hr.resume.line', 'read', [resume_ids],
                              {'fields': ['name', 'line_type_id', 'date_start', 'date_end']})
            for r in (resume_data or []):
                resume_found.append({
                    'name': r.get('name', ''),
                    'type': get_name(r.get('line_type_id')),
                    'date_start': r.get('date_start', ''),
                    'date_end': r.get('date_end', ''),
                })
        emp_result['resume_lines'] = resume_found

result['employee'] = emp_result

# ===================================================================
# 4. Check Leave Allocation
# ===================================================================
alloc_result = {'exists': False}
if emp_ids:
    alloc_ids = exe('hr.leave.allocation', 'search', [[
        ['employee_id', '=', emp_ids[0]],
        ['holiday_status_id', '=', gt['pto_leave_type_id']],
    ]])
    if alloc_ids:
        alloc_data = exe('hr.leave.allocation', 'read', [[alloc_ids[0]]],
                         {'fields': ['number_of_days', 'state', 'holiday_status_id', 'employee_id']})
        if alloc_data:
            al = alloc_data[0]
            alloc_result = {
                'exists': True,
                'days': al.get('number_of_days', 0),
                'state': al.get('state', ''),
                'is_validated': al.get('state', '') == 'validate',
                'is_20_days': al.get('number_of_days', 0) == 20,
            }
    # Also check with broader search in case leave type name varies
    if not alloc_result.get('exists'):
        all_alloc_ids = exe('hr.leave.allocation', 'search', [[['employee_id', '=', emp_ids[0]]]])
        if all_alloc_ids:
            all_alloc_data = exe('hr.leave.allocation', 'read', [all_alloc_ids],
                                 {'fields': ['number_of_days', 'state', 'holiday_status_id']})
            for al in (all_alloc_data or []):
                lt_name = get_name(al.get('holiday_status_id')) or ''
                if 'paid' in lt_name.lower() or 'pto' in lt_name.lower() or 'time off' in lt_name.lower():
                    alloc_result = {
                        'exists': True,
                        'days': al.get('number_of_days', 0),
                        'state': al.get('state', ''),
                        'is_validated': al.get('state', '') == 'validate',
                        'is_20_days': al.get('number_of_days', 0) == 20,
                        'leave_type_name': lt_name,
                    }
                    break
result['allocation'] = alloc_result

# ===================================================================
# 5. Pass through ground truth IDs for verifier
# ===================================================================
result['gt'] = gt

with open('/tmp/hiring_pipeline_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: {json.dumps(result, indent=2)}")
PYTHON_EOF

chmod 666 /tmp/hiring_pipeline_result.json 2>/dev/null || true
echo "=== complete_hiring_pipeline export complete ==="
