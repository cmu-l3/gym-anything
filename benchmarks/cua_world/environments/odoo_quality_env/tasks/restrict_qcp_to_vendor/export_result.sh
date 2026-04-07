#!/bin/bash
echo "=== Exporting restrict_qcp_to_vendor result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export state to JSON using Python/XML-RPC
# We export the state here so the host-side verifier can read it via copy_from_env
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import time
import sys
import os

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

output_file = "/tmp/task_result.json"
task_start_file = "/tmp/task_start_time.txt"

def get_start_time():
    try:
        if os.path.exists(task_start_file):
            with open(task_start_file, 'r') as f:
                return float(f.read().strip())
    except:
        pass
    return 0.0

def main():
    start_time = get_start_time()
    result = {
        "timestamp": time.time(),
        "task_start_time": start_time,
        "qcp_exists": False,
        "qcp_data": {},
        "target_partner_found": False,
        "target_partner_id": None
    }
    
    try:
        common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
        uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
        models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")
        
        # 1. Find the QCP
        qcp_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.point', 'search', [[['title', '=', 'Cabinet Inspection']]])
        
        if qcp_ids:
            result["qcp_exists"] = True
            # Read relevant fields: partner_id, product_ids, picking_type_ids, write_date
            fields = ['partner_id', 'product_ids', 'picking_type_ids', 'write_date']
            qcp_data = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.point', 'read', [qcp_ids, fields])[0]
            result["qcp_data"] = qcp_data
            
        # 2. Find Gemini Furniture ID to verify against
        partner_ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'res.partner', 'search', [[['name', '=', 'Gemini Furniture']]])
        if partner_ids:
            result["target_partner_found"] = True
            result["target_partner_id"] = partner_ids[0]
            
    except Exception as e:
        result["error"] = str(e)
        
    # Write result
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
    print(f"Result exported to {output_file}")

if __name__ == "__main__":
    main()
PYTHON_EOF

# Set permissions so we can copy it out
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="