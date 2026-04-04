#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract data from Odoo using Python
# We need to export: Opportunity Name, Partner Country Code, List of Tag Names
python3 << 'PYEOF'
import xmlrpc.client
import json
import os
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, passwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Define the opportunities we care about
    target_opp_names = [
        'Waffle Iron Bulk Order',
        'Logistics Software Upgrade',
        'Cloud Server Migration',
        'Fleet Tracking System'
    ]

    # Search for these opportunities
    ids = models.execute_kw(db, uid, passwd, 'crm.lead', 'search', [[['name', 'in', target_opp_names]]])
    
    # Read relevant fields: name, country_id (via partner), tag_ids
    # country_id on crm.lead is actually a related field to partner_id.country_id, usually stored.
    # However, to be safe, we'll fetch partner_id and traverse.
    leads = models.execute_kw(db, uid, passwd, 'crm.lead', 'read', [ids], {'fields': ['name', 'partner_id', 'tag_ids']})

    export_data = []

    for lead in leads:
        # Get partner country
        country_code = "Unknown"
        if lead['partner_id']:
            partner_id = lead['partner_id'][0] # [id, name]
            partner = models.execute_kw(db, uid, passwd, 'res.partner', 'read', [partner_id], {'fields': ['country_id']})[0]
            if partner['country_id']:
                country_id = partner['country_id'][0]
                country = models.execute_kw(db, uid, passwd, 'res.country', 'read', [country_id], {'fields': ['code']})[0]
                country_code = country['code']
        
        # Get Tag Names
        tag_names = []
        if lead['tag_ids']:
            tags = models.execute_kw(db, uid, passwd, 'crm.tag', 'read', [lead['tag_ids']], {'fields': ['name']})
            tag_names = [t['name'] for t in tags]

        export_data.append({
            'name': lead['name'],
            'country_code': country_code,
            'tags': tag_names
        })

    # Save to JSON
    result = {
        "opportunities": export_data,
        "task_start": int(os.environ.get('TASK_START', 0)),
        "task_end": int(os.environ.get('TASK_END', 0)),
        "screenshot_path": "/tmp/task_final.png"
    }
    
    # Use temp file and move to avoid permission issues
    with open('/tmp/temp_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(f"Error exporting data: {e}")
    # Write error json
    with open('/tmp/temp_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)

PYEOF

# Move result to final location with permissive permissions
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="