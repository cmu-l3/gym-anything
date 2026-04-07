#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query Odoo for the result
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

def connect():
    try:
        common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
        uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
        models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")
        return uid, models
    except Exception as e:
        print(f"Connection failed: {e}", file=sys.stderr)
        return None, None

def get_setup_info():
    try:
        with open('/tmp/setup_info.json', 'r') as f:
            return json.load(f)
    except:
        return {}

def main():
    setup_info = get_setup_info()
    alert_id = setup_info.get('alert_id')
    expected_vendor_id = setup_info.get('vendor_id')
    
    result = {
        "alert_found": False,
        "partner_id": None,
        "partner_name": None,
        "write_date": None,
        "correct_vendor_linked": False,
        "data_integrity_ok": False,
        "alert_id": alert_id
    }
    
    uid, models = connect()
    if not uid:
        with open('/tmp/task_result.json', 'w') as f:
            json.dump(result, f)
        return

    # Fetch the alert
    # We search by ID from setup, but if that's gone, we try by name to see if they recreated it
    fields = ['name', 'partner_id', 'product_id', 'write_date']
    alert_data = []
    
    if alert_id:
        alert_data = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.alert', 'read', 
            [[alert_id], fields])
    
    if not alert_data:
        # Fallback: Search by name
        print("Alert ID not found, searching by name...")
        ids = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.alert', 'search',
            [[['name', '=', 'Surface Defects on Cabinet Batch']]])
        if ids:
            alert_data = models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, 'quality.alert', 'read',
                [[ids[0]], fields])

    if alert_data:
        record = alert_data[0]
        result["alert_found"] = True
        result["write_date"] = record.get("write_date")
        
        # Check partner (Many2one field returns [id, name] or False)
        partner_field = record.get("partner_id")
        if partner_field:
            result["partner_id"] = partner_field[0]
            result["partner_name"] = partner_field[1]
            
            # Verification logic inside export to simplify verifier
            if result["partner_id"] == expected_vendor_id:
                result["correct_vendor_linked"] = True
            elif result["partner_name"] == "Wood Corner":
                # Handle case where agent created a duplicate vendor
                result["correct_vendor_linked"] = True
                result["note"] = "Vendor matched by name (ID mismatch)"
        
        # Check integrity
        if record.get("name") == "Surface Defects on Cabinet Batch":
            result["data_integrity_ok"] = True

    # Save result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
    
    print("Export complete.")

if __name__ == "__main__":
    main()
PYTHON_EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="