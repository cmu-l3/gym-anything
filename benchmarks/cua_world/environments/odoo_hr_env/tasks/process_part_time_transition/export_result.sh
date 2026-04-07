#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract data from Odoo via Python/XML-RPC
# We need:
# - Current work schedule for Audrey Peterson
# - Recent log notes on her record
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import datetime
import os
import sys

# Read task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start_time = float(f.read().strip())
except:
    task_start_time = 0

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "task_start_time": task_start_time,
    "timestamp": datetime.datetime.utcnow().isoformat(),
    "employee_found": False,
    "current_schedule": None,
    "log_notes": []
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find Audrey
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Audrey Peterson']]])
    
    if emp_ids:
        result["employee_found"] = True
        emp_id = emp_ids[0]
        
        # Get Work Schedule
        emp_data = models.execute_kw(db, uid, password, 'hr.employee', 'read', [emp_id, ['resource_calendar_id']])
        if emp_data and emp_data[0]['resource_calendar_id']:
            # resource_calendar_id returns [id, "Name"]
            result["current_schedule"] = emp_data[0]['resource_calendar_id'][1]
        
        # Get Log Notes (mail.message)
        # We look for messages linked to this employee created AFTER task start
        # Note: Odoo dates are UTC strings. We fetch recent 20 and filter in Python to be safe.
        messages = models.execute_kw(db, uid, password, 'mail.message', 'search_read', 
            [[
                ['model', '=', 'hr.employee'],
                ['res_id', '=', emp_id],
                ['message_type', 'in', ['comment', 'notification']], 
                ['body', '!=', False]
            ]],
            {'fields': ['body', 'date', 'subtype_id', 'author_id'], 'limit': 20, 'order': 'date desc'}
        )
        
        for msg in messages:
            # Simple check: if msg date is recent. 
            # Odoo date format: "%Y-%m-%d %H:%M:%S"
            msg_dt = datetime.datetime.strptime(msg['date'], "%Y-%m-%d %H:%M:%S")
            # Approximate conversion to timestamp (assuming Odoo is UTC, which it usually is internally)
            msg_ts = msg_dt.replace(tzinfo=datetime.timezone.utc).timestamp()
            
            # Allow 60s buffer for clock drift/container time diffs
            if msg_ts > (task_start_time - 60):
                result["log_notes"].append({
                    "body": msg['body'],
                    "date": msg['date']
                })

except Exception as e:
    result["error"] = str(e)

# Write to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYTHON_EOF

# 3. Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="