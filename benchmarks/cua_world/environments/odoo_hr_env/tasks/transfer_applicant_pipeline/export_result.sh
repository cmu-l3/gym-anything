#!/bin/bash
echo "=== Exporting Transfer Applicant Pipeline Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract data from Odoo using Python/XML-RPC
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import os
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'
task_start_ts = 0

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start_ts = int(f.read().strip())
except:
    pass

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the applicant
    applicant_ids = models.execute_kw(db, uid, password, 'hr.applicant', 'search', [[['partner_name', '=', 'Alex Morgan']]])
    
    result_data = {
        "found": False,
        "job_position": None,
        "department": None,
        "tags": [],
        "notes": [],
        "write_date": None,
        "task_start_ts": task_start_ts
    }

    if applicant_ids:
        app_id = applicant_ids[0]
        # Read fields
        fields = ['job_id', 'department_id', 'category_ids', 'write_date']
        data = models.execute_kw(db, uid, password, 'hr.applicant', 'read', [app_id], {'fields': fields})[0]
        
        result_data["found"] = True
        
        # Odoo returns (id, name) for many2one fields
        result_data["job_position"] = data['job_id'][1] if data['job_id'] else None
        result_data["department"] = data['department_id'][1] if data['department_id'] else None
        result_data["write_date"] = data['write_date']

        # Handle tags (many2many)
        if data['category_ids']:
            tags = models.execute_kw(db, uid, password, 'hr.applicant.category', 'read', [data['category_ids']], {'fields': ['name']})
            result_data["tags"] = [t['name'] for t in tags]
            
        # Check chatter messages (mail.message)
        # Looking for messages created after task start linked to this applicant
        # Note: Odoo timestamps are UTC. Python xmlrpc usually handles datetime conversion, but let's be safe.
        # We'll fetch the last 10 messages and filter in Python or verification logic.
        message_ids = models.execute_kw(db, uid, password, 'mail.message', 'search', 
            [[['model', '=', 'hr.applicant'], ['res_id', '=', app_id], ['message_type', '=', 'comment']]],
            {'limit': 10, 'order': 'date desc'})
            
        if message_ids:
            messages = models.execute_kw(db, uid, password, 'mail.message', 'read', [message_ids], {'fields': ['body', 'date', 'author_id']})
            # Clean HTML body
            for msg in messages:
                result_data["notes"].append({
                    "body": msg['body'],
                    "date": msg['date']
                })

    # Save to JSON
    with open(output_file, 'w') as f:
        # Custom serializer for datetime objects if necessary (though json dump might fail if not handled)
        # Odoo XMLRPC returns strings for dates usually, but let's be safe
        json.dump(result_data, f, default=str, indent=2)

    print(f"Exported data to {output_file}")

except Exception as e:
    print(f"Error exporting result: {e}")
    # Write a failure json
    with open(output_file, 'w') as f:
        json.dump({"error": str(e), "found": False}, f)

PYTHON_EOF

# Set permissions so ga user/verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="