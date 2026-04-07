#!/bin/bash
echo "=== Exporting create_sales_order results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Extract database state to JSON via Python script inside container/host
cat > /tmp/export_db.py << 'PYEOF'
import json
import subprocess
import os

def run_query(query):
    cmd = ["docker", "exec", "vtiger-db", "mysql", "-u", "vtiger", "-pvtiger_pass", "vtiger", "-N", "-e", query]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except Exception as e:
        return ""

result = {}
# Read initial states
try:
    with open('/tmp/initial_so_count.txt', 'r') as f:
        result['initial_count'] = int(f.read().strip())
except:
    result['initial_count'] = 0

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start_time'] = int(f.read().strip())
except:
    result['task_start_time'] = 0

result['current_count'] = int(run_query("SELECT COUNT(*) FROM vtiger_salesorder") or 0)

# Check for the target Sales Order
so_data = run_query("SELECT salesorderid, subject, sostatus, duedate, total FROM vtiger_salesorder WHERE subject LIKE '%GF-SEASONAL%' ORDER BY salesorderid DESC LIMIT 1")

if so_data:
    parts = so_data.split('\t')
    so_id = parts[0]
    result['sales_order'] = {
        'id': so_id,
        'subject': parts[1],
        'status': parts[2],
        'duedate': parts[3],
        'total': float(parts[4]) if len(parts) > 4 and parts[4] else 0.0
    }
    
    # Get linked Organization
    org = run_query(f"SELECT a.accountname FROM vtiger_account a JOIN vtiger_salesorder so ON so.accountid=a.accountid WHERE so.salesorderid={so_id}")
    result['sales_order']['organization'] = org
    
    # Get linked Contact
    contact = run_query(f"SELECT CONCAT(c.firstname, ' ', c.lastname) FROM vtiger_contactdetails c JOIN vtiger_salesorder so ON so.contactid=c.contactid WHERE so.salesorderid={so_id}")
    result['sales_order']['contact'] = contact
    
    # Get creation timestamp
    created = run_query(f"SELECT UNIX_TIMESTAMP(createdtime) FROM vtiger_crmentity WHERE crmid={so_id}")
    result['sales_order']['created_time'] = int(created) if created else 0

    # Get Line Items
    items_data = run_query(f"SELECT p.productname, i.quantity, i.listprice FROM vtiger_inventoryproductrel i JOIN vtiger_products p ON p.productid=i.productid WHERE i.id={so_id}")
    items = []
    if items_data:
        for line in items_data.split('\n'):
            if line.strip():
                iparts = line.split('\t')
                items.append({
                    'name': iparts[0],
                    'quantity': float(iparts[1]) if len(iparts) > 1 and iparts[1] else 0.0,
                    'price': float(iparts[2]) if len(iparts) > 2 and iparts[2] else 0.0
                })
    result['sales_order']['line_items'] = items

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

python3 /tmp/export_db.py
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="