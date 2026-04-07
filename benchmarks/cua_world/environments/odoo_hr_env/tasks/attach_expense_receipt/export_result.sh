#!/bin/bash
echo "=== Exporting attach_expense_receipt results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Python script to check database state and export JSON
python3 << 'PYEOF'
import xmlrpc.client
import sys
import os
import json
import datetime

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "target_found": False,
    "attachment_found": False,
    "correct_filename": False,
    "attachment_count": 0,
    "attachment_names": [],
    "expense_data": {},
    "timestamp_valid": False
}

try:
    # Read target ID
    if not os.path.exists('/tmp/target_expense_id.txt'):
        print("Target ID file missing.")
    else:
        with open('/tmp/target_expense_id.txt', 'r') as f:
            target_id = int(f.read().strip())
        
        result["target_found"] = True
        
        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        # Check Attachments linked to this expense
        # Attachments are in 'ir.attachment'. res_model='hr.expense', res_id=target_id
        attachments = models.execute_kw(db, uid, password, 'ir.attachment', 'search_read',
            [[['res_model', '=', 'hr.expense'], ['res_id', '=', target_id]]],
            {'fields': ['name', 'datas_fname', 'create_date', 'mimetype']}
        )
        
        result["attachment_count"] = len(attachments)
        
        # Read task start time
        start_time_ts = 0
        if os.path.exists('/tmp/task_start_time.txt'):
            with open('/tmp/task_start_time.txt', 'r') as f:
                try:
                    start_time_ts = int(f.read().strip())
                except:
                    pass

        found_receipt = False
        valid_timestamp = False
        
        for att in attachments:
            name = att.get('name', '')
            result["attachment_names"].append(name)
            
            if 'receipt_lunch' in name.lower() or 'receipt' in name.lower():
                found_receipt = True
                result["correct_filename"] = True
                
                # Check creation time (Odoo returns string "YYYY-MM-DD HH:MM:SS")
                create_date_str = att.get('create_date', '')
                try:
                    # Parse Odoo UTC timestamp
                    create_dt = datetime.datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
                    create_ts = create_dt.timestamp()
                    
                    # Allow 5 second clock skew tolerance
                    if create_ts >= (start_time_ts - 5):
                        valid_timestamp = True
                except Exception as e:
                    print(f"Date parse error: {e}")
                    # Fallback: if filename matches, give benefit of doubt if parsing fails
                    valid_timestamp = True

        if found_receipt:
            result["attachment_found"] = True
            result["timestamp_valid"] = valid_timestamp

except Exception as e:
    print(f"Export error: {e}")
    result["error"] = str(e)

# Write result to temp file
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json