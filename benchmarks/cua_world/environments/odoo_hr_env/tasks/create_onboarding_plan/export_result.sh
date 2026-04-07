#!/bin/bash
echo "=== Exporting Create Onboarding Plan results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve stored data
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELI_ID=$(cat /tmp/target_employee_id.txt 2>/dev/null || echo "0")

# -------------------------------------------------------
# Query Odoo for Final State
# -------------------------------------------------------
echo "Querying Odoo database..."
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

def get_odoo_data():
    try:
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # 1. Check for the Plan
        plan_domain = [['name', '=', 'New Employee Onboarding']]
        plan_fields = ['id', 'name', 'template_ids']
        plans = models.execute_kw(db, uid, password, 'mail.activity.plan', 'search_read',
                                  [plan_domain], {'fields': plan_fields})
        
        plan_data = None
        templates_data = []
        
        if plans:
            plan_data = plans[0]
            # 2. Check Templates linked to the plan
            # Note: template_ids is a list of IDs in Odoo 17
            tmpl_ids = plan_data.get('template_ids', [])
            if tmpl_ids:
                tmpl_fields = ['summary', 'responsible_type', 'activity_type_id']
                templates_data = models.execute_kw(db, uid, password, 'mail.activity.plan.template', 'read',
                                                   [tmpl_ids], {'fields': tmpl_fields})

        # 3. Check Activities on Eli Lambert
        # We look for activities created recently
        emp_id = int("$ELI_ID")
        activity_domain = [
            ['res_model', '=', 'hr.employee'],
            ['res_id', '=', emp_id]
        ]
        activity_fields = ['summary', 'user_id', 'create_date', 'activity_type_id']
        activities = models.execute_kw(db, uid, password, 'mail.activity', 'search_read',
                                       [activity_domain], {'fields': activity_fields})

        return {
            "plan_found": bool(plans),
            "plan_details": plan_data,
            "templates": templates_data,
            "employee_activities": activities,
            "eli_id": emp_id
        }

    except Exception as e:
        return {"error": str(e)}

# Serialize with default string conversion for dates
data = get_odoo_data()
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, default=str)

PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="