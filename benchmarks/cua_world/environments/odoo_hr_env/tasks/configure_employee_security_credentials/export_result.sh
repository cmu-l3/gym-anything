#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Extract data from Odoo using Python/XML-RPC
# We fetch the current state of the target employees to compare against expectations
python3 << PYTHON_EOF
import xmlrpc.client
import json
import os
import datetime
import time

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

output_file = '/tmp/task_result.json'
result = {
    "task_start_ts": int("$TASK_START_TS"),
    "employees": {},
    "timestamp": datetime.datetime.now().isoformat(),
    "connection_error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    target_names = ['Anita Oliver', 'Toni Jimenez', 'Jeffrey Kelly']
    
    # Fetch employee data including write_date (last modification)
    domain = [['name', 'in', target_names]]
    fields = ['name', 'barcode', 'pin', 'write_date']
    
    employees = models.execute_kw(db, uid, password, 'hr.employee', 'search_read', [domain], {'fields': fields})
    
    for emp in employees:
        # Convert Odoo's write_date (string UTC) to Unix timestamp for easy comparison
        write_date_str = emp.get('write_date', '')
        write_ts = 0
        if write_date_str:
            # Odoo 17 format usually "YYYY-MM-DD HH:MM:SS" (UTC)
            # handle potential variations just in case
            try:
                dt = datetime.datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
                # Assume UTC
                write_ts = dt.replace(tzinfo=datetime.timezone.utc).timestamp()
            except ValueError:
                pass
        
        result['employees'][emp['name']] = {
            "id": emp['id'],
            "barcode": emp.get('barcode', False),
            "pin": emp.get('pin', False),
            "write_date": write_date_str,
            "write_ts": write_ts
        }

except Exception as e:
    result["connection_error"] = str(e)
    print(f"Error querying Odoo: {e}")

# Save results to a temporary file first
temp_path = f"{output_file}.tmp"
with open(temp_path, 'w') as f:
    json.dump(result, f, indent=2)

# Atomic move to ensure valid file
os.rename(temp_path, output_file)
# Ensure readable by everyone (verifier runs as user)
os.chmod(output_file, 0o666)

print(f"Exported results to {output_file}")
PYTHON_EOF

cat /tmp/task_result.json
echo "=== Export complete ==="