#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query Odoo state and dump to JSON
python3 << 'PYEOF'
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
task_start = int(os.environ.get('TASK_START', 0))

output = {
    "task_start": task_start,
    "timestamp": datetime.now().isoformat(),
    "work_location_found": False,
    "work_location": {},
    "employees": {}
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    if not uid:
        print("Auth failed", file=sys.stderr)
        output["error"] = "Authentication failed"
    else:
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        
        # 1. Check for the Work Location
        target_name = "East Side Satellite Office"
        # Search case-insensitive to be lenient, but we prefer exact match
        wl_ids = models.execute_kw(db, uid, 'admin', 'hr.work.location', 'search',
                                    [[['name', '=', target_name]]])
        
        target_wl_id = None
        
        if wl_ids:
            target_wl_id = wl_ids[0]
            wl_data = models.execute_kw(db, uid, 'admin', 'hr.work.location', 'read',
                                         [[target_wl_id]], 
                                         {'fields': ['name', 'location_type', 'create_date']})
            if wl_data:
                record = wl_data[0]
                output["work_location_found"] = True
                output["work_location"] = {
                    "id": record.get("id"),
                    "name": record.get("name"),
                    "location_type": record.get("location_type"),
                    "create_date": record.get("create_date")
                }
        else:
            # Fallback check for close matches (case insensitive)
            all_wl = models.execute_kw(db, uid, 'admin', 'hr.work.location', 'search_read',
                                        [[]], {'fields': ['id', 'name']})
            for wl in all_wl:
                if target_name.lower() in wl['name'].lower():
                    output["work_location_found"] = True # Partial match found
                    target_wl_id = wl['id']
                    output["work_location"] = {
                        "id": wl['id'],
                        "name": wl['name'], 
                        "location_type": "unknown", # Didn't fetch details yet
                        "note": "Approximate name match"
                    }
                    # Fetch details for the partial match
                    details = models.execute_kw(db, uid, 'admin', 'hr.work.location', 'read',
                                                 [[target_wl_id]], {'fields': ['location_type', 'create_date']})
                    if details:
                        output["work_location"].update(details[0])
                    break

        # 2. Check Employees assignments
        target_employees = ["Marc Demo", "Audrey Peterson", "Randall Lewis"]
        for emp_name in target_employees:
            emp_data = models.execute_kw(db, uid, 'admin', 'hr.employee', 'search_read',
                                          [[['name', '=', emp_name]]],
                                          {'fields': ['id', 'name', 'work_location_id']})
            
            emp_info = {"found": False, "assigned_wl_id": None, "assigned_wl_name": None}
            
            if emp_data:
                emp_info["found"] = True
                wl_field = emp_data[0].get('work_location_id') # returns [id, name] or False
                if wl_field:
                    emp_info["assigned_wl_id"] = wl_field[0]
                    emp_info["assigned_wl_name"] = wl_field[1]
            
            output["employees"][emp_name] = emp_info

except Exception as e:
    output["error"] = str(e)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print("Export completed. content of /tmp/task_result.json:")
print(json.dumps(output, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="