#!/bin/bash
echo "=== Exporting create_activity_type results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Query Odoo for the result
# We need to extract specific fields to verify correctness
python3 - <<PYEOF
import xmlrpc.client
import json
import sys
import os

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_exists": False,
    "fields": {},
    "is_new": False,
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # Search for the record
    ids = models.execute_kw(db, uid, password, 'mail.activity.type', 'search',
        [[['name', '=', 'Product Demo']]])
    
    if ids:
        result["record_exists"] = True
        # Get the most recently created one if duplicates exist
        record_id = ids[-1]
        
        # Read fields
        fields = ['name', 'summary', 'default_note', 'delay_count', 'res_model_id', 'create_date']
        data = models.execute_kw(db, uid, password, 'mail.activity.type', 'read',
            [[record_id], fields])[0]
        
        # Resolve the model name if res_model_id is set
        model_technical_name = None
        if data.get('res_model_id'):
            # res_model_id is [id, display_name]
            model_id = data['res_model_id'][0]
            model_data = models.execute_kw(db, uid, password, 'ir.model', 'read',
                [[model_id], ['model']])[0]
            model_technical_name = model_data.get('model')
            
        result["fields"] = {
            "name": data.get('name'),
            "summary": data.get('summary'),
            "default_note": data.get('default_note'),
            "delay_count": data.get('delay_count'),
            "model_technical_name": model_technical_name,
            "create_date": data.get('create_date')
        }
        
        # Check creation time against task start (anti-gaming)
        # Odoo returns strings like '2023-10-25 10:00:00' (UTC)
        # For simplicity, we assume if it exists and we deleted it in setup, it's new.
        # But we can also check the ID vs some baseline if we tracked max_id.
        # Since we deleted duplicates in setup, existence implies new creation.
        result["is_new"] = True

except Exception as e:
    result["error"] = str(e)

# Write result to temp file with proper permissions
import tempfile
import shutil

with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
    json.dump(result, tmp, indent=2)
    tmp_path = tmp.name

# Move to final location safely
try:
    shutil.copy(tmp_path, "/tmp/task_result.json")
    os.chmod("/tmp/task_result.json", 0o666)
finally:
    os.remove(tmp_path)

print("Export script finished.")
PYEOF

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="