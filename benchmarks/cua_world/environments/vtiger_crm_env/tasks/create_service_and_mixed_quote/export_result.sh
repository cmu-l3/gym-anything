#!/bin/bash
echo "=== Exporting create_service_and_mixed_quote results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract database state securely into JSON using Python
python3 - << 'EOF'
import json
import subprocess
import os

def query_db(query_str):
    try:
        cmd = [
            "docker", "exec", "vtiger-db", "mysql", 
            "-u", "vtiger", "-pvtiger_pass", "vtiger", 
            "-N", "-e", query_str
        ]
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return result.decode('utf-8').strip()
    except Exception as e:
        return ""

def read_initial_count(filepath):
    try:
        with open(filepath, 'r') as f:
            return int(f.read().strip() or "0")
    except:
        return 0

# Initial counts
initial_service_count = read_initial_count('/tmp/initial_service_count.txt')
initial_quote_count = read_initial_count('/tmp/initial_quote_count.txt')

# Current counts
curr_service_data = query_db("SELECT COUNT(*) FROM vtiger_service")
current_service_count = int(curr_service_data) if curr_service_data.isdigit() else 0

curr_quote_data = query_db("SELECT COUNT(*) FROM vtiger_quotes")
current_quote_count = int(curr_quote_data) if curr_quote_data.isdigit() else 0

result = {
    "initial_service_count": initial_service_count,
    "initial_quote_count": initial_quote_count,
    "current_service_count": current_service_count,
    "current_quote_count": current_quote_count,
    "service_found": False,
    "quote_found": False,
    "line_items": []
}

# Find target Service
service_data = query_db("SELECT s.serviceid, s.servicename, s.unit_price, s.service_usageunit FROM vtiger_service s INNER JOIN vtiger_crmentity e ON s.serviceid=e.crmid WHERE s.servicename='Network Installation & Setup' AND e.deleted=0 LIMIT 1")

if service_data:
    parts = service_data.split('\t')
    if len(parts) >= 4:
        result["service_found"] = True
        result["service"] = {
            "id": parts[0],
            "name": parts[1],
            "price": float(parts[2]) if parts[2].replace('.', '', 1).isdigit() else 0.0,
            "unit": parts[3]
        }

# Find target Quote
quote_data = query_db("SELECT q.quoteid, q.subject, q.accountid, q.contactid, b.bill_street FROM vtiger_quotes q INNER JOIN vtiger_crmentity e ON q.quoteid=e.crmid LEFT JOIN vtiger_quotesbillads b ON q.quoteid=b.quotebilladdressid WHERE q.subject='TechNova - Branch Network Setup' AND e.deleted=0 LIMIT 1")

if quote_data:
    parts = quote_data.split('\t')
    if len(parts) >= 5:
        result["quote_found"] = True
        q_id = parts[0]
        result["quote"] = {
            "id": q_id,
            "subject": parts[1],
            "accountid": parts[2],
            "contactid": parts[3],
            "bill_street": parts[4]
        }
        
        # Get line items
        lines_data = query_db(f"SELECT rel.quantity, p.productname, s.servicename FROM vtiger_inventoryproductrel rel LEFT JOIN vtiger_products p ON p.productid=rel.productid LEFT JOIN vtiger_service s ON s.serviceid=rel.productid WHERE rel.id={q_id}")
        
        if lines_data:
            for line in lines_data.split('\n'):
                lparts = line.split('\t')
                if len(lparts) >= 3:
                    qty = float(lparts[0]) if lparts[0].replace('.', '', 1).isdigit() else 0.0
                    pname = lparts[1] if lparts[1] != 'NULL' else ""
                    sname = lparts[2] if lparts[2] != 'NULL' else ""
                    
                    item_name = pname if pname else sname
                    item_type = "Product" if pname else "Service" if sname else "Unknown"
                    
                    result["line_items"].append({
                        "quantity": qty,
                        "name": item_name.strip(),
                        "type": item_type
                    })

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="