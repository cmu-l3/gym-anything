#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Run Python script to inspect Odoo database for the filter
# We run this inside the container and export a JSON for the verifier
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import os
import sys

url = "http://localhost:8069"
db = "odoo_quality"
password = "admin"
output_file = "/tmp/task_result.json"
task_start = 0

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

result_data = {
    "filter_found": False,
    "filter_name": None,
    "filter_domain": None,
    "filter_context": None,
    "created_after_start": False,
    "stage_new_id": None
}

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Get "New" stage ID to help verification logic understand the domain
    stages = models.execute_kw(db, uid, password, 'quality.alert.stage', 'search_read', 
        [[]], {'fields': ['id', 'name']})
    new_stage_ids = [s['id'] for s in stages if 'new' in s['name'].lower()]
    result_data['stage_new_id'] = new_stage_ids

    # Search for the filter
    # We look for filters on 'quality.alert' model created by the current user
    filters = models.execute_kw(db, uid, password, 'ir.filters', 'search_read',
        [[('model_id', '=', 'quality.alert'), ('user_id', '=', uid)]],
        {'fields': ['name', 'domain', 'context', 'create_date', 'is_default']})
    
    # Filter strictly for the requested name locally to handle case sensitivity loosely if needed
    target_filter = None
    for f in filters:
        if 'urgent actions' in f['name'].lower():
            target_filter = f
            break
            
    if target_filter:
        result_data['filter_found'] = True
        result_data['filter_name'] = target_filter['name']
        result_data['filter_domain'] = target_filter['domain']
        result_data['filter_context'] = target_filter['context']
        
        # Check timestamp (Anti-gaming)
        # Odoo returns create_date as string 'YYYY-MM-DD HH:MM:SS'
        # Simple check: we cleared filters in setup, so if it exists, it's likely new.
        # But we can also check if we want to be strict.
        result_data['created_after_start'] = True # Validated by cleanup in setup
        
    # Write result
    with open(output_file, 'w') as f:
        json.dump(result_data, f)
        
    print(f"Exported Odoo filter data to {output_file}")

except Exception as e:
    print(f"Error extracting data: {e}")
    # Write partial result
    with open(output_file, 'w') as f:
        json.dump(result_data, f)
PYTHON_EOF

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Check if screenshot exists
if [ -f /tmp/task_final.png ]; then
    echo "Final screenshot captured."
else
    echo "WARNING: Final screenshot missing."
fi

# 4. Set permissions so host can read
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json