#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Python script to query final state from Odoo
cat > /tmp/query_final_state.py << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "applicant_found": False,
    "stage_name": None,
    "tags": [],
    "messages": [],
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find Alex Morgan
    # We search by partner_name since name might be "Consultant - Alex Morgan"
    applicants = models.execute_kw(db, uid, password, 'hr.applicant', 'search_read',
                                   [[['partner_name', '=', 'Alex Morgan']]],
                                   {'fields': ['id', 'stage_id', 'categ_ids'], 'limit': 1})
    
    if applicants:
        app = applicants[0]
        result["applicant_found"] = True
        
        # Get Stage Name
        # stage_id is [id, "Name"]
        if app.get('stage_id'):
            result["stage_name"] = app['stage_id'][1]

        # Get Tag Names
        # categ_ids is a list of IDs. Need to fetch names.
        tag_ids = app.get('categ_ids', [])
        if tag_ids:
            tags = models.execute_kw(db, uid, password, 'hr.applicant.category', 'read',
                                     [tag_ids], {'fields': ['name']})
            result["tags"] = [t['name'] for t in tags]

        # Get Chatter Messages
        # Search mail.message for this model and res_id
        # We limit to messages created recently to avoid noise (though unlikely in clean setup)
        # But for simplicity, just get all comments/notes.
        msg_ids = models.execute_kw(db, uid, password, 'mail.message', 'search',
                                    [[['model', '=', 'hr.applicant'], 
                                      ['res_id', '=', app['id']], 
                                      ['message_type', 'in', ['comment', 'notification']]]])
        
        if msg_ids:
            messages = models.execute_kw(db, uid, password, 'mail.message', 'read',
                                         [msg_ids], {'fields': ['body', 'date', 'message_type']})
            # Clean HTML body slightly for verification readability
            for msg in messages:
                result["messages"].append({
                    "body": msg.get('body', ''),
                    "type": msg.get('message_type')
                })

except Exception as e:
    result["error"] = str(e)

# Output JSON
print(json.dumps(result))
PYTHON_EOF

# Run query and save to file
python3 /tmp/query_final_state.py > /tmp/query_output.json

# Merge with system info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

jq -n \
    --slurpfile query /tmp/query_output.json \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    '{
        task_start: $start,
        task_end: $end,
        odoo_data: $query[0]
    }' > /tmp/task_result.json

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="