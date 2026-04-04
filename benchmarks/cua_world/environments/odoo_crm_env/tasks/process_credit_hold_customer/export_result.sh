#!/bin/bash
echo "=== Exporting Process Customer Credit Hold results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Export database state to JSON using Python
python3 << PYEOF > /tmp/task_result.json
import xmlrpc.client
import json
import time
from datetime import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

result = {
    "lost_reason_created": False,
    "lost_reason_correct_name": False,
    "tag_created": False,
    "tag_correct_name": False,
    "partner_tagged": False,
    "opportunity_lost": False,
    "opportunity_reason_correct": False,
    "created_during_task": False,
    "timestamp": str(datetime.now())
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
    
    task_start_ts = ${TASK_START}

    # 1. Check Lost Reason
    reasons = models.execute_kw(db, uid, password, 'crm.lost.reason', 'search_read', 
        [[['name', '=', 'Credit Issues']]], 
        {'fields': ['id', 'name', 'create_date']})
    
    if reasons:
        result["lost_reason_created"] = True
        result["lost_reason_correct_name"] = True
        # Check timestamp (Odoo stores UTC strings, simple check if ID exists is usually enough for functional verification, 
        # but strict check would parse date. Here we assume if it exists and wasn't there at start (setup cleared it), it's good.)
        
    # 2. Check Tag
    tags = models.execute_kw(db, uid, password, 'res.partner.category', 'search_read',
        [[['name', '=', 'Credit Hold']]],
        {'fields': ['id', 'name']})
        
    tag_id = None
    if tags:
        result["tag_created"] = True
        result["tag_correct_name"] = True
        tag_id = tags[0]['id']

    # 3. Check Partner
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search_read',
        [[['name', '=', 'Gemini Furniture']]],
        {'fields': ['id', 'category_id']})
        
    if partners and tag_id:
        # category_id is a list of IDs in Odoo many2many
        if tag_id in partners[0]['category_id']:
            result["partner_tagged"] = True

    # 4. Check Opportunity
    leads = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
        [[['name', '=', 'Gemini - Office Chairs'], ['active', '=', False]]], 
        {'fields': ['id', 'active', 'lost_reason_id']})
    
    if leads:
        result["opportunity_lost"] = True
        # lost_reason_id is (id, name) tuple or False
        reason_val = leads[0]['lost_reason_id']
        if reason_val and reason_val[1] == 'Credit Issues':
            result["opportunity_reason_correct"] = True
            
    # Simple anti-gaming check: if we found the objects that we cleared in setup, 
    # they must have been created during the task.
    if result["lost_reason_created"] and result["tag_created"]:
        result["created_during_task"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="