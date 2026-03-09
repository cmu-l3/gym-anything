#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to extract verification data
python3 - <<PYEOF
import xmlrpc.client
import json
import time
import sys

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eur_active": False,
    "opportunity_found": False,
    "opportunity_data": {},
    "currency_data": {}
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # 1. Check EUR Currency Status
    eur_data = models.execute_kw(db, uid, password, 'res.currency', 'search_read', 
        [[['name', '=', 'EUR']]], 
        {'fields': ['id', 'name', 'active', 'write_date']})
    
    if eur_data:
        eur_rec = eur_data[0]
        result['eur_active'] = eur_rec.get('active', False)
        result['currency_data'] = eur_rec
        result['eur_id'] = eur_rec['id']
    
    # 2. Check Opportunity
    opp_name = "Munich Warehouse Solar Installation"
    opp_data = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
        [[['name', '=', opp_name]]],
        {'fields': ['id', 'name', 'expected_revenue', 'currency_id', 'partner_id', 'create_date']})

    if opp_data:
        # Get the most recently created one if duplicates exist
        opp = sorted(opp_data, key=lambda x: x['id'], reverse=True)[0]
        result['opportunity_found'] = True
        
        # Normalize currency_id field (returns [id, name] list in Odoo read)
        curr_id = opp.get('currency_id')
        if isinstance(curr_id, list) and len(curr_id) > 0:
             curr_id = curr_id[0]
        
        # Normalize partner_id field
        part_id = opp.get('partner_id')
        part_name = ""
        if isinstance(part_id, list) and len(part_id) > 1:
            part_name = part_id[1]
            part_id = part_id[0]
        
        result['opportunity_data'] = {
            'id': opp['id'],
            'expected_revenue': opp.get('expected_revenue'),
            'currency_id': curr_id,
            'partner_name': part_name,
            'create_date': opp.get('create_date')
        }

except Exception as e:
    result['error'] = str(e)
    print(f"Error extracting data: {e}", file=sys.stderr)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="