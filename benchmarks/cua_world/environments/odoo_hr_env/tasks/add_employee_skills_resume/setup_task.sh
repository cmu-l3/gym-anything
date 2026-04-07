#!/bin/bash
set -e
echo "=== Setting up add_employee_skills_resume task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Setup Database State via Python/XML-RPC
# - Install hr_skills module if needed
# - Create Skill Types (IT, Languages) and Levels
# - Ensure Eli Lambert exists and clean his skills/resume
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # --- 1. Install hr_skills module if not installed ---
    module_id = models.execute_kw(db, uid, password, 'ir.module.module', 'search', [[['name', '=', 'hr_skills']]])
    if module_id:
        module_data = models.execute_kw(db, uid, password, 'ir.module.module', 'read', [module_id], {'fields': ['state']})
        if module_data and module_data[0]['state'] != 'installed':
            print("Installing hr_skills module...")
            models.execute_kw(db, uid, password, 'ir.module.module', 'button_immediate_install', [module_id])
            print("hr_skills installed.")
    
    # --- 2. Setup Skill Types and Levels ---
    # Define IT Skill Type
    it_type_ids = models.execute_kw(db, uid, password, 'hr.skill.type', 'search', [[['name', '=', 'IT']]])
    if not it_type_ids:
        it_type_id = models.execute_kw(db, uid, password, 'hr.skill.type', 'create', [{'name': 'IT'}])
        # Create levels for IT
        levels = [('Beginner', 25), ('Intermediate', 50), ('Advanced', 75), ('Expert', 100)]
        for name, progress in levels:
             models.execute_kw(db, uid, password, 'hr.skill.level', 'create', [{
                 'name': name, 'skill_type_id': it_type_id, 'level_progress': progress
             }])
        # Create Python skill
        models.execute_kw(db, uid, password, 'hr.skill', 'create', [{'name': 'Python', 'skill_type_id': it_type_id}])
    else:
        it_type_id = it_type_ids[0]
        # Ensure Python exists
        skill_ids = models.execute_kw(db, uid, password, 'hr.skill', 'search', [[['name', '=', 'Python'], ['skill_type_id', '=', it_type_id]]])
        if not skill_ids:
            models.execute_kw(db, uid, password, 'hr.skill', 'create', [{'name': 'Python', 'skill_type_id': it_type_id}])

    # Define Languages Skill Type
    lang_type_ids = models.execute_kw(db, uid, password, 'hr.skill.type', 'search', [[['name', '=', 'Languages']]])
    if not lang_type_ids:
        lang_type_id = models.execute_kw(db, uid, password, 'hr.skill.type', 'create', [{'name': 'Languages'}])
        levels = [('Beginner', 25), ('Intermediate', 50), ('Advanced', 75), ('Expert', 100)]
        for name, progress in levels:
             models.execute_kw(db, uid, password, 'hr.skill.level', 'create', [{
                 'name': name, 'skill_type_id': lang_type_id, 'level_progress': progress
             }])
        models.execute_kw(db, uid, password, 'hr.skill', 'create', [{'name': 'Spanish', 'skill_type_id': lang_type_id}])
    else:
        lang_type_id = lang_type_ids[0]
        skill_ids = models.execute_kw(db, uid, password, 'hr.skill', 'search', [[['name', '=', 'Spanish'], ['skill_type_id', '=', lang_type_id]]])
        if not skill_ids:
            models.execute_kw(db, uid, password, 'hr.skill', 'create', [{'name': 'Spanish', 'skill_type_id': lang_type_id}])

    # --- 3. Setup Resume Line Types ---
    exp_type_ids = models.execute_kw(db, uid, password, 'hr.resume.line.type', 'search', [[['name', '=', 'Experience']]])
    if not exp_type_ids:
        models.execute_kw(db, uid, password, 'hr.resume.line.type', 'create', [{'name': 'Experience', 'sequence': 1}])

    # --- 4. Clean Eli Lambert's Data ---
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
    if emp_ids:
        emp_id = emp_ids[0]
        # Delete existing skills
        skill_ids = models.execute_kw(db, uid, password, 'hr.employee.skill', 'search', [[['employee_id', '=', emp_id]]])
        if skill_ids:
            models.execute_kw(db, uid, password, 'hr.employee.skill', 'unlink', [skill_ids])
            print(f"Cleared {len(skill_ids)} skills for Eli Lambert")
        
        # Delete existing resume lines
        resume_ids = models.execute_kw(db, uid, password, 'hr.resume.line', 'search', [[['employee_id', '=', emp_id]]])
        if resume_ids:
            models.execute_kw(db, uid, password, 'hr.resume.line', 'unlink', [resume_ids])
            print(f"Cleared {len(resume_ids)} resume lines for Eli Lambert")
    else:
        print("ERROR: Eli Lambert not found")
        sys.exit(1)

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 3. Launch/Focus Firefox and Navigate
# Navigate to the Employee list to force the agent to find the employee
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# 4. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="