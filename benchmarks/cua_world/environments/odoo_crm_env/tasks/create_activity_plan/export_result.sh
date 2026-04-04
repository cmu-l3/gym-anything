#!/bin/bash
echo "=== Exporting create_activity_plan results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to fetch the current state of Plans and Activities
# We export the raw data to JSON so the host verifier can parse and score it.
python3 - << 'PYEOF'
import xmlrpc.client
import json
import datetime
import sys

# Helper for JSON serialization of dates
def json_serial(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    raise TypeError (f"Type {type(obj)} not serializable")

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

result_data = {
    "plan_found": False,
    "plan_steps": [],
    "activities_found": [],
    "opportunity_found": False
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # 1. Inspect the Activity Plan
    plans = models.execute_kw(db, uid, password, 'mail.activity.plan', 'search_read',
        [[['name', '=', 'Standard Outreach']]],
        {'fields': ['id', 'name', 'template_ids']})
        
    if plans:
        result_data["plan_found"] = True
        plan = plans[0]
        
        # Get the templates (steps)
        if plan['template_ids']:
            templates = models.execute_kw(db, uid, password, 'mail.activity.plan.template', 'search_read',
                [[['id', 'in', plan['template_ids']]]],
                {'fields': ['summary', 'plan_date_deadline_interval', 'activity_type_id']})
            result_data["plan_steps"] = templates

    # 2. Inspect Activities on the Opportunity
    opps = models.execute_kw(db, uid, password, 'crm.lead', 'search',
        [[['name', '=', 'Acme Corp Inquiry']]])
        
    if opps:
        result_data["opportunity_found"] = True
        opp_id = opps[0]
        
        # Fetch activities
        activities = models.execute_kw(db, uid, password, 'mail.activity', 'search_read',
            [[['res_id', '=', opp_id], ['res_model', '=', 'crm.lead']]],
            {'fields': ['summary', 'date_deadline', 'activity_type_id', 'create_date']})
        result_data["activities_found"] = activities

except Exception as e:
    result_data["error"] = str(e)

# Write to temp file
with open('/tmp/export_data.json', 'w') as f:
    json.dump(result_data, f, default=json_serial)
PYEOF

# Create final result JSON with system stats + data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "odoo_data": $(cat /tmp/export_data.json)
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/export_data.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="