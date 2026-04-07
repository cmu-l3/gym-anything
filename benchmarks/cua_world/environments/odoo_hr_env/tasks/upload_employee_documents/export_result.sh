#!/bin/bash
echo "=== Exporting upload_employee_documents results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract data via Python/XML-RPC
# We need to find messages attached to Eli Lambert created after task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

python3 << PYTHON_EOF
import xmlrpc.client
import json
import time
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
task_start_time = $TASK_START

result = {
    "employee_found": False,
    "notes_found": [],
    "attachments_found": [],
    "task_start_time": task_start_time,
    "timestamp": time.time()
}

try:
    # Connect
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find Employee
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Eli Lambert']]])
    
    if emp_ids:
        result["employee_found"] = True
        emp_id = emp_ids[0]
        
        # Search for messages (notes) linked to this employee
        # Criteria: model=hr.employee, res_id=emp_id, date > task_start
        # Note: Odoo dates are strings, so we fetch recent ones and filter in python to be safe/easy
        messages = models.execute_kw(db, uid, password, 'mail.message', 'search_read',
            [[
                ['model', '=', 'hr.employee'],
                ['res_id', '=', emp_id],
                ['message_type', '=', 'comment'] # 'comment' is usually used for notes/chatter
            ]],
            {'fields': ['body', 'date', 'attachment_ids', 'is_internal', 'subtype_id']}
        )
        
        # Filter messages created after task start
        # Odoo date format: "YYYY-MM-DD HH:MM:SS"
        # We'll just look at the most recent ones if exact timestamp conversion is tricky in minimal python
        # But we can try to be robust.
        
        # Simplify: Just grab messages that have our specific text, then check attachments
        for msg in messages:
            # Check for attachments
            att_ids = msg.get('attachment_ids', [])
            att_names = []
            if att_ids:
                attachments = models.execute_kw(db, uid, password, 'ir.attachment', 'read', [att_ids], {'fields': ['name', 'create_date']})
                for att in attachments:
                    att_names.append({
                        "name": att['name'],
                        "id": att['id']
                    })
            
            result["notes_found"].append({
                "id": msg['id'],
                "body": msg.get('body', ''),
                "is_internal": msg.get('is_internal', False),
                "attachments": att_names
            })

except Exception as e:
    result["error"] = str(e)

# Write to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported data to /tmp/task_result.json")
PYTHON_EOF

# Set permissions so we can copy it out
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="