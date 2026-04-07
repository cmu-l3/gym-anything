#!/bin/bash
# Export script for expense_claim_reimbursement task
# Queries ERPNext for new Expense Claims and Payment Entries linked to Marco Silva.
# Writes results to /tmp/expense_claim_reimbursement_result.json.

echo "=== Exporting expense_claim_reimbursement results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/expense_claim_reimbursement_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

try:
    with open("/tmp/expense_claim_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

existing_ec_names = set(baseline.get("existing_expense_claims", []))
existing_pe_names = set(baseline.get("existing_payment_entries", []))

def api_get(doctype, filters=None, fields=None, limit=20):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# --- 1. Export New Expense Claims for Marco Silva ---
# Filter only submitted claims (docstatus=1)
all_ecs = api_get("Expense Claim",
                   [["employee_name", "like", "%Marco%Silva%"], ["docstatus", "=", 1]],
                   fields=["name", "employee", "employee_name", "total_claimed_amount", "docstatus"])

new_ecs = []
for ec in all_ecs:
    if ec["name"] not in existing_ec_names:
        # Fetch full doc to get child items
        doc = get_doc("Expense Claim", ec["name"])
        expenses = doc.get("expenses", [])
        
        new_ecs.append({
            "ec_name": ec["name"],
            "total_claimed_amount": float(ec.get("total_claimed_amount", 0)),
            "expense_count": len(expenses),
            "expenses": [{"expense_type": x.get("expense_type"), "amount": x.get("amount", 0)} for x in expenses]
        })

# --- 2. Export New Payment Entries for Marco Silva ---
# Filter only submitted payments (docstatus=1)
all_pes = api_get("Payment Entry",
                   [["party_type", "=", "Employee"], ["party_name", "like", "%Marco%Silva%"], ["docstatus", "=", 1]],
                   fields=["name", "party", "party_name", "paid_amount", "payment_type", "docstatus"])

new_pes = []
for pe in all_pes:
    if pe["name"] not in existing_pe_names:
        new_pes.append({
            "pe_name": pe["name"],
            "payment_type": pe.get("payment_type"),
            "paid_amount": float(pe.get("paid_amount", 0))
        })

result = {
    "employee": "Marco Silva",
    "expense_claims": new_ecs,
    "payment_entries": new_pes
}

with open("/tmp/expense_claim_reimbursement_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/expense_claim_reimbursement_result.json ===")
PYEOF

echo "=== Export done ==="