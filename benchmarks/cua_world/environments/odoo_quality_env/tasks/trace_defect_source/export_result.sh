#!/bin/bash
echo "=== Exporting trace_defect_source results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python script to inspect database state and export to JSON
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import os
from datetime import datetime

url = "http://localhost:8069"
db = "odoo_quality"
username = "admin"
password = "admin"

result = {
    "alert_found": False,
    "picking_linked": False,
    "picking_origin": None,
    "priority": "0",
    "write_date": None,
    "task_start_time": 0
}

try:
    # Get task start time
    if os.path.exists("/tmp/task_start_time.txt"):
        with open("/tmp/task_start_time.txt", "r") as f:
            result["task_start_time"] = int(f.read().strip())

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Find the alert
    alert_ids = models.execute_kw(db, uid, password, 'quality.alert', 'search',
        [[['name', '=', 'Defective Office Chair']]])
    
    if alert_ids:
        result["alert_found"] = True
        alert_data = models.execute_kw(db, uid, password, 'quality.alert', 'read', 
            [alert_ids[0]], ['picking_id', 'priority', 'write_date'])
        
        data = alert_data[0]
        result["priority"] = str(data.get('priority', '0'))
        result["write_date"] = data.get('write_date')
        
        # Check Picking
        picking_field = data.get('picking_id') # [id, name] or False
        if picking_field:
            result["picking_linked"] = True
            picking_id = picking_field[0]
            
            # Read picking origin
            picking_data = models.execute_kw(db, uid, password, 'stock.picking', 'read',
                [picking_id], ['origin'])
            if picking_data:
                result["picking_origin"] = picking_data[0].get('origin')

    # Write result to file
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)
        
    print("Exported result:", json.dumps(result))

except Exception as e:
    print(f"Export Error: {e}")
    # Write empty/error result
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": str(e)}, f)

PYEOF

echo "=== Export complete ==="