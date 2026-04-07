#!/bin/bash
echo "=== Exporting update_employee_home_address results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state of Audrey Peterson's address
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import datetime
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "employee_found": False,
    "address_linked": False,
    "street": "",
    "city": "",
    "zip": "",
    "state_name": "",
    "country_name": "",
    "write_date": ""
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find Employee
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
        [[['name', '=', 'Audrey Peterson']]])
    
    if emp_ids:
        result["employee_found"] = True
        emp = models.execute_kw(db, uid, password, 'hr.employee', 'read',
            [emp_ids[0]], {'fields': ['address_home_id']})[0]
        
        address_link = emp['address_home_id'] # Returns (id, name) or False
        
        if address_link:
            result["address_linked"] = True
            addr_id = address_link[0]
            
            # Read partner address fields
            partner = models.execute_kw(db, uid, password, 'res.partner', 'read',
                [addr_id], {'fields': ['street', 'street2', 'city', 'zip', 'state_id', 'country_id', 'write_date']})[0]
            
            # Combine street and street2 for easier checking
            street_full = (partner['street'] or "") + " " + (partner['street2'] or "")
            
            result["street"] = street_full.strip()
            result["city"] = partner['city'] or ""
            result["zip"] = partner['zip'] or ""
            result["write_date"] = partner['write_date']
            
            # Resolve Many2One fields (returns (id, name) tuple)
            if partner['state_id']:
                result["state_name"] = partner['state_id'][1]
            if partner['country_id']:
                result["country_name"] = partner['country_id'][1]

except Exception as e:
    result["error"] = str(e)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

PYTHON_EOF

# Set permissions so ga user/verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json