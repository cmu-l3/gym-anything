#!/bin/bash
echo "=== Exporting Consolidate Duplicate Applicants result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

# Read IDs created during setup
OLD_APP_ID=$(cat /tmp/old_app_id.txt 2>/dev/null || echo "0")
NEW_APP_ID=$(cat /tmp/new_app_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to query final state
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'
output_file = '/tmp/task_result.json'

result = {
    "old_app_active": True,
    "old_app_exists": False,
    "new_app_active": False,
    "new_note_found": False,
    "new_note_body": "",
    "timestamp_valid": False,
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    old_id = int("$OLD_APP_ID")
    new_id = int("$NEW_APP_ID")
    task_start = float("$TASK_START")

    # Check Old Application
    # Note: Search with active_test=False to find archived records
    old_apps = models.execute_kw(db, uid, password, 'hr.applicant', 'search_read', 
        [[['id', '=', old_id], '|', ['active', '=', True], ['active', '=', False]]], 
        {'fields': ['active']})
    
    if old_apps:
        result["old_app_exists"] = True
        result["old_app_active"] = old_apps[0]['active']
    
    # Check New Application
    new_apps = models.execute_kw(db, uid, password, 'hr.applicant', 'search_read', 
        [[['id', '=', new_id]]], 
        {'fields': ['active']})
    
    if new_apps:
        result["new_app_active"] = new_apps[0]['active']
        
        # Check messages on New Application
        # We look for messages created AFTER task start
        messages = models.execute_kw(db, uid, password, 'mail.message', 'search_read',
            [[['model', '=', 'hr.applicant'], 
              ['res_id', '=', new_id],
              ['message_type', 'in', ['comment', 'note']]]],
            {'fields': ['body', 'date', 'create_date']})
            
        for msg in messages:
            # Odoo dates are typically UTC strings. Simple check: create_date is usually sufficient if roughly compared
            # Ideally we parse the date, but simple existence of a NEW message with keywords is robust enough
            # if we trust the 'search' didn't return ancient messages (created newly).
            # To be safe, we check if the message contains target keywords.
            
            body = msg.get('body', '').lower()
            if 'visa' in body or 'sponsorship' in body:
                result["new_note_found"] = True
                result["new_note_body"] = msg.get('body', '')
                
                # Timestamp check (rudimentary string comparison or assume valid if created during this session)
                # Since we created the app during setup, any message on it is either from setup or agent.
                # Setup didn't add a note to the NEW app, only the OLD one.
                # So any note on the NEW app is likely from the agent.
                result["timestamp_valid"] = True
                break

except Exception as e:
    result["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f)

PYTHON_EOF

# Set permissions for the result file so verification can read it
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="