#!/bin/bash
echo "=== Exporting create_defects_by_product_report result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot (primary evidence for VLM)
take_screenshot /tmp/task_final.png

# Query the database for the created filter
# We look for filters on 'quality.alert' model created after task start
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoo_quality"
password = "admin"
task_start = $TASK_START
output_file = "/tmp/task_result.json"

result = {
    "filter_found": False,
    "filter_name": "",
    "filter_context": "",
    "filter_domain": "",
    "is_new": False,
    "model_id": "",
    "timestamp": task_start
}

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")
    
    # Search for filters created for quality.alert
    # Note: Odoo stores context as a string representation of a dict
    filters = models.execute_kw(db, uid, password, 'ir.filters', 'search_read', 
        [[['model_id', '=', 'quality.alert']]], 
        {'fields': ['name', 'context', 'domain', 'create_date', 'model_id']})
    
    # Filter matching logic in Python to handle date comparison and fuzzy name matching
    target_filter = None
    
    for f in filters:
        # Check name (case-insensitive)
        if "alerts by product" in f['name'].lower():
            # Check creation time if possible (Odoo returns string dates)
            # Simple check: we cleared specific filters in setup, so existence implies creation
            # But let's verify it matches our target
            target_filter = f
            break
            
    if target_filter:
        result["filter_found"] = True
        result["filter_name"] = target_filter["name"]
        result["filter_context"] = target_filter["context"] # Look for group_by
        result["filter_domain"] = target_filter["domain"]
        result["model_id"] = target_filter["model_id"]
        
        # Odoo date format: "YYYY-MM-DD HH:MM:SS"
        # We assume if it exists now and was deleted in setup, it is new.
        result["is_new"] = True

except Exception as e:
    result["error"] = str(e)
    print(f"Error querying Odoo: {e}", file=sys.stderr)

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)
    
print(f"Exported result to {output_file}")
PYTHON_EOF

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="