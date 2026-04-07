#!/bin/bash
# Export script for bank_reconciliation task
# Queries ERPNext for Bank Transactions on 'First National Bank - WP' 
# and exports their status and PE links.

echo "=== Exporting bank_reconciliation results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/bank_reconciliation_final.png 2>/dev/null || true

python3 << PYEOF
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

try:
    with open("/tmp/bank_recon_baseline.json") as f:
        baseline = json.load(f)
    bank_acc_name = baseline.get("bank_acc_name", "First National Bank - WP")
    initial_reconciled = baseline.get("initial_reconciled", 0)
except Exception:
    bank_acc_name = "First National Bank - WP"
    initial_reconciled = 0

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# Fetch all Bank Transactions for this account
bt_list = api_get("Bank Transaction", [["bank_account", "=", bank_acc_name]])

results = []
for bt in bt_list:
    doc = get_doc("Bank Transaction", bt["name"])
    pes = doc.get("payment_entries", [])
    
    # Extract just the essential parts to save space
    linked_vouchers = [pe.get("payment_document") for pe in pes if pe.get("payment_document")]
    
    results.append({
        "name": doc.get("name"),
        "status": doc.get("status"),
        "description": doc.get("description"),
        "deposit": doc.get("deposit", 0),
        "withdrawal": doc.get("withdrawal", 0),
        "payment_entries_count": len(linked_vouchers),
        "linked_vouchers": linked_vouchers
    })

output = {
    "task_start_time": $TASK_START,
    "bank_acc_name": bank_acc_name,
    "initial_reconciled": initial_reconciled,
    "transactions": results
}

with open("/tmp/bank_reconciliation_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
print("\n=== Export complete: /tmp/bank_reconciliation_result.json ===")
PYEOF

echo "=== Export done ==="