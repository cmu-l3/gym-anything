#!/bin/bash
echo "=== Exporting HR Onboarding Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to query Odoo state and export to JSON
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'
RESULT_PATH = '/tmp/hr_onboarding_result.json'

result = {
    "timestamp": datetime.datetime.now().isoformat(),
    "department": None,
    "job": None,
    "schedule": None,
    "employees": [],
    "error": None
}

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        raise Exception("Authentication failed")
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

    # 1. Check Department "Quality Assurance"
    dept_ids = models.execute_kw(DB, uid, PASSWORD, 'hr.department', 'search_read',
        [[['name', 'ilike', 'Quality Assurance']]],
        {'fields': ['id', 'name', 'manager_id']})
    
    if dept_ids:
        result['department'] = dept_ids[0]
        # Resolve manager name if assigned
        if result['department']['manager_id']:
            mgr_id = result['department']['manager_id'][0]
            mgr_data = models.execute_kw(DB, uid, PASSWORD, 'hr.employee', 'read', [mgr_id], {'fields': ['name']})
            if mgr_data:
                result['department']['manager_name'] = mgr_data[0]['name']

    # 2. Check Job "QA Inspector"
    job_ids = models.execute_kw(DB, uid, PASSWORD, 'hr.job', 'search_read',
        [[['name', 'ilike', 'QA Inspector']]],
        {'fields': ['id', 'name', 'department_id']})
    
    if job_ids:
        result['job'] = job_ids[0]

    # 3. Check Schedule "QA Shift Schedule"
    calendar_ids = models.execute_kw(DB, uid, PASSWORD, 'resource.calendar', 'search_read',
        [[['name', 'ilike', 'QA Shift Schedule']]],
        {'fields': ['id', 'name', 'attendance_ids']})
    
    if calendar_ids:
        cal = calendar_ids[0]
        # Get attendance details (days of week)
        attendances = models.execute_kw(DB, uid, PASSWORD, 'resource.calendar.attendance', 'read',
            [cal['attendance_ids']],
            {'fields': ['dayofweek', 'hour_from', 'hour_to']})
        
        # Odoo days: 0=Mon, 6=Sun
        days_present = sorted(list(set([int(a['dayofweek']) for a in attendances])))
        cal['days_of_week'] = days_present
        result['schedule'] = cal

    # 4. Check Employees
    target_names = ['Maria Chen', 'James Okafor', 'Sarah Petrov']
    for name in target_names:
        emp_data = models.execute_kw(DB, uid, PASSWORD, 'hr.employee', 'search_read',
            [[['name', 'ilike', name]]],
            {'fields': ['id', 'name', 'work_email', 'work_phone', 'department_id', 'job_id', 'coach_id', 'resource_calendar_id']})
        
        if emp_data:
            emp = emp_data[0]
            # Resolve relation names for easier verification
            if emp['department_id']: emp['department_name'] = emp['department_id'][1]
            if emp['job_id']: emp['job_name'] = emp['job_id'][1]
            if emp['coach_id']: emp['coach_name'] = emp['coach_id'][1]
            if emp['resource_calendar_id']: emp['calendar_name'] = emp['resource_calendar_id'][1]
            
            result['employees'].append(emp)

except Exception as e:
    result['error'] = str(e)

with open(RESULT_PATH, 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to safe location and permissions
cp /tmp/hr_onboarding_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="