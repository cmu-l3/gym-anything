#!/bin/bash
set -e
echo "=== Exporting log_note_on_opportunity results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LEAD_ID=$(cat /tmp/target_lead_id.txt 2>/dev/null || echo "0")
INITIAL_MSG_COUNT=$(cat /tmp/initial_msg_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract data using Python/XML-RPC
python3 << PYEOF
import xmlrpc.client
import json
import os
import sys
from datetime import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

result_data = {
    "task_start": int("$TASK_START"),
    "task_end": int("$TASK_END"),
    "lead_id": int("$LEAD_ID"),
    "initial_msg_count": int("$INITIAL_MSG_COUNT"),
    "messages": [],
    "final_msg_count": 0,
    "screenshot_path": "/tmp/task_final.png"
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # Get current message count
    final_count = models.execute_kw(db, uid, password, 'mail.message', 'search_count', 
        [[['res_model', '=', 'crm.lead'], ['res_id', '=', int("$LEAD_ID")]]])
    result_data["final_msg_count"] = final_count

    # Fetch messages created after task start
    # Note: Odoo stores dates in UTC. We'll fetch recent messages and filter in python to be safe
    # or just fetch the last few messages.
    msg_ids = models.execute_kw(db, uid, password, 'mail.message', 'search', 
        [[['res_model', '=', 'crm.lead'], ['res_id', '=', int("$LEAD_ID")]]],
        {'limit': 10, 'order': 'id desc'})
    
    if msg_ids:
        messages = models.execute_kw(db, uid, password, 'mail.message', 'read', 
            [msg_ids], 
            {'fields': ['id', 'date', 'body', 'message_type', 'subtype_id', 'author_id']})
        
        # Clean data for JSON export
        for msg in messages:
            # Flatten subtype_id (comes as [id, "Name"])
            subtype = "Unknown"
            if msg.get('subtype_id'):
                subtype = msg['subtype_id'][1]
            msg['subtype_name'] = subtype
            
            # Clean body (simple HTML strip or keep raw)
            msg['body_raw'] = msg.get('body', '')
            
            result_data["messages"].append(msg)

except Exception as e:
    result_data["error"] = str(e)
    print(f"Error fetching data: {e}", file=sys.stderr)

# Save to JSON
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result_data, f, indent=4)
PYEOF

# Move with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="