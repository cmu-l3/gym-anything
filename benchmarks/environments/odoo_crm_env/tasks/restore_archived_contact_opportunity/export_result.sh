#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting: restore_archived_contact_opportunity ==="

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get task start timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python/XML-RPC to fetch all necessary data structured as JSON
# This is more robust than parsing raw SQL output for complex relations
python3 << PYEOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
pwd = "admin"

output = {
    "contact_active": False,
    "contact_phone": "",
    "contact_city": "",
    "contact_street": "",
    "contact_state": "",
    "contact_write_date_epoch": 0,
    "opportunity_exists": False,
    "opportunity_revenue": 0.0,
    "opportunity_priority": "0",
    "opportunity_partner_name": "",
    "opportunity_create_date_epoch": 0,
    "task_start_time": ${TASK_START}
}

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, user, pwd, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # 1. Fetch Contact Data
    # We search active=True to verify it was restored.
    partners = models.execute_kw(db, uid, pwd, 'res.partner', 'search_read',
        [[['name', '=', 'Meridian Technologies'], ['active', '=', True]]],
        {'fields': ['phone', 'city', 'street', 'state_id', 'write_date'], 'limit': 1})

    if partners:
        p = partners[0]
        output["contact_active"] = True
        output["contact_phone"] = p.get('phone') or ""
        output["contact_city"] = p.get('city') or ""
        output["contact_street"] = p.get('street') or ""
        # state_id is (id, name) tuple
        output["contact_state"] = p.get('state_id')[1] if p.get('state_id') else ""
        
        # Parse write_date to epoch
        if p.get('write_date'):
            dt = datetime.datetime.strptime(p['write_date'], "%Y-%m-%d %H:%M:%S")
            output["contact_write_date_epoch"] = int(dt.timestamp())

    # 2. Fetch Opportunity Data
    opps = models.execute_kw(db, uid, pwd, 'crm.lead', 'search_read',
        [[['name', '=', 'Meridian Technologies - Enterprise Software Renewal']]],
        {'fields': ['expected_revenue', 'priority', 'partner_id', 'create_date'], 'limit': 1})

    if opps:
        o = opps[0]
        output["opportunity_exists"] = True
        output["opportunity_revenue"] = o.get('expected_revenue') or 0.0
        output["opportunity_priority"] = o.get('priority') or "0"
        # partner_id is (id, name) tuple
        output["opportunity_partner_name"] = o.get('partner_id')[1] if o.get('partner_id') else ""
        
        # Parse create_date to epoch
        if o.get('create_date'):
            dt = datetime.datetime.strptime(o['create_date'], "%Y-%m-%d %H:%M:%S")
            output["opportunity_create_date_epoch"] = int(dt.timestamp())

except Exception as e:
    output["error"] = str(e)

# Write to temp file with proper permissions
temp_path = "/tmp/result_temp.json"
with open(temp_path, "w") as f:
    json.dump(output, f, indent=4)

PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/result_temp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="