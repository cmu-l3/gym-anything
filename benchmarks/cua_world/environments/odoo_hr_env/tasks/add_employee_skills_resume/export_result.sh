#!/bin/bash
echo "=== Exporting add_employee_skills_resume results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python script to query Odoo and verify data
# We check:
# - Existing skills for Eli Lambert
# - Existing resume lines for Eli Lambert
# - Timestamps (create_date) vs Task Start Time

python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os
import datetime

# Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start_ts = float(f.read().strip())
    # Odoo stores times in UTC database-side, but usually RPC returns strings.
    # We will fetch create_date and convert.
except:
    task_start_ts = 0

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "task_start_ts": task_start_ts,
    "skills_found": [],
    "resume_lines_found": [],
    "app_running": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    result["app_running"] = True

    # Find Eli Lambert
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
    if emp_ids:
        emp_id = emp_ids[0]
        
        # 1. Query Skills
        # Fields: skill_id.name, skill_level_id.name, skill_type_id.name, create_date
        skill_ids = models.execute_kw(db, uid, password, 'hr.employee.skill', 'search', [[['employee_id', '=', emp_id]]])
        if skill_ids:
            skills = models.execute_kw(db, uid, password, 'hr.employee.skill', 'read', [skill_ids], 
                                     ['skill_id', 'skill_level_id', 'skill_type_id', 'create_date'])
            for s in skills:
                # Odoo returns (id, name) tuples for M2O fields usually, or just lookups
                # read returns: 'skill_id': [1, 'Python']
                skill_name = s['skill_id'][1] if s['skill_id'] else ""
                level_name = s['skill_level_id'][1] if s['skill_level_id'] else ""
                type_name = s['skill_type_id'][1] if s['skill_type_id'] else ""
                create_date_str = s['create_date'] # Format: 'YYYY-MM-DD HH:MM:SS'
                
                # Check timestamp (simple string comparison ok if task started recently, but proper parsing better)
                # Odoo 17 create_date is UTC
                dt = datetime.datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
                # Assume container is UTC or match timestamps. 
                # Simplest anti-gaming: check if created AFTER task start
                created_ts = dt.timestamp()
                
                result["skills_found"].append({
                    "skill": skill_name,
                    "level": level_name,
                    "type": type_name,
                    "created_after_start": created_ts >= task_start_ts
                })

        # 2. Query Resume Lines
        # Fields: name, line_type_id.name, date_start, date_end, description
        resume_ids = models.execute_kw(db, uid, password, 'hr.resume.line', 'search', [[['employee_id', '=', emp_id]]])
        if resume_ids:
            lines = models.execute_kw(db, uid, password, 'hr.resume.line', 'read', [resume_ids],
                                    ['name', 'line_type_id', 'date_start', 'date_end', 'create_date'])
            for l in lines:
                name = l['name']
                line_type = l['line_type_id'][1] if l['line_type_id'] else ""
                date_start = l['date_start']
                date_end = l['date_end']
                create_date_str = l['create_date']
                
                dt = datetime.datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
                created_ts = dt.timestamp()

                result["resume_lines_found"].append({
                    "name": name,
                    "type": line_type,
                    "date_start": date_start,
                    "date_end": date_end,
                    "created_after_start": created_ts >= task_start_ts
                })

except Exception as e:
    result["error"] = str(e)

# Save to /tmp/task_result.json
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json