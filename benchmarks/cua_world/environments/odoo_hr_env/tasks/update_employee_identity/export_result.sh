#!/bin/bash
echo "=== Exporting update_employee_identity result ==="

# Source utils for screenshot
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Odoo via XML-RPC to get the final state of the employee
# We output a JSON object directly from Python
python3 << PYTHON_EOF > /tmp/odoo_query_result.json
import xmlrpc.client
import json
import sys
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "employee_found": False,
    "image_present": False,
    "barcode_value": None,
    "write_date": None,
    "write_date_ts": 0
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
    
    # Fetch fields
    emp_data = models.execute_kw(db, uid, password, 'hr.employee', 'search_read', 
        [[['name', '=', 'Anita Oliver']]], 
        {'fields': ['image_1920', 'barcode', 'write_date']}
    )
    
    if emp_data:
        emp = emp_data[0]
        result["employee_found"] = True
        
        # Check if image is present (it returns binary data or False)
        # We don't export the full binary, just boolean presence
        result["image_present"] = bool(emp.get('image_1920'))
        
        # Get barcode
        result["barcode_value"] = emp.get('barcode')
        
        # Get write date (UTC string from Odoo)
        w_date = emp.get('write_date')
        result["write_date"] = w_date
        
        # Convert Odoo datetime string to timestamp for easy comparison
        if w_date:
            try:
                # Odoo 17 format usually: "YYYY-MM-DD HH:MM:SS"
                dt = datetime.strptime(w_date, "%Y-%m-%d %H:%M:%S")
                result["write_date_ts"] = int(dt.timestamp())
            except ValueError:
                pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYTHON_EOF

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
ODOO_RESULT=$(cat /tmp/odoo_query_result.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odoo_state": $ODOO_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"
rm -f /tmp/odoo_query_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="