#!/bin/bash
echo "=== Exporting results: Structure Unformatted Leads ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the current state of our tracked leads
# We search by the 'description' field which contains our hidden REF_IDs
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, passwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    refs = ["REF_LEAD_001", "REF_LEAD_002", "REF_LEAD_003"]
    results = {}

    for ref in refs:
        # Search by description to find the specific record
        ids = models.execute_kw(db, uid, passwd, 'crm.lead', 'search', [[['description', 'ilike', ref]]])
        
        if ids:
            # Read relevant fields
            data = models.execute_kw(db, uid, passwd, 'crm.lead', 'read', 
                [ids], 
                {'fields': ['name', 'contact_name', 'priority', 'description']})[0]
            
            results[ref] = {
                "found": True,
                "name": data.get('name'),
                "contact_name": data.get('contact_name'),
                "priority": data.get('priority')
            }
        else:
            results[ref] = {"found": False}

    # Save to JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(results, f, indent=2)
    print("Exported lead data to /tmp/task_result.json")

except Exception as e:
    print(f"Error exporting data: {e}", file=sys.stderr)
    # Create empty result file on error to prevent cascading failures
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)

PYEOF

# Ensure permissions are open for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="