#!/bin/bash
# Setup script for expense_claim_reimbursement task
# Creates the Engineering department, the employee Marco Silva, and Expense Claim Types.
# Saves a baseline to ensure the agent creates NEW records.

set -e
echo "=== Setting up expense_claim_reimbursement ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext to be ready..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# Wait for ERPNext master data (before_tests completion)
print("Waiting for ERPNext master data (Company)...")
master_ready = False
for attempt in range(100):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        if companies:
            print(f"  Master data ready after {attempt * 15}s")
            master_ready = True
            break
    except Exception:
        pass
    print(f"  Master data not ready yet... ({attempt * 15}s elapsed)", flush=True)
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available after 25 minutes", file=sys.stderr)
    sys.exit(1)

# Re-login
session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})

def get_or_create(doctype, filters, values):
    existing = api_get(doctype, filters)
    if existing:
        name = existing[0]["name"]
        print(f"  Found existing {doctype}: {name}")
        return name
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        name = r.json().get("data", {}).get("name", "unknown")
        print(f"  Created {doctype}: {name}")
        return name
    print(f"  ERROR creating {doctype}: {r.status_code} {r.text[:300]}", file=sys.stderr)
    return None

# 1. Setup Department
print("Setting up Engineering department...")
get_or_create("Department",
              [["department_name", "=", "Engineering"]],
              {"department_name": "Engineering",
               "company": "Wind Power LLC",
               "parent_department": "All Departments"})

# 2. Setup Expense Claim Types
expense_types = ["Accommodation", "Airfare", "Ground Transportation", "Meals and Entertainment"]
print("Setting up Expense Claim Types...")
for et in expense_types:
    get_or_create("Expense Claim Type", [["name", "=", et]], {"name": et, "expense_type": et})

# 3. Setup Employee: Marco Silva
print("Setting up Employee: Marco Silva...")
emp_def = {
    "employee_name": "Marco Silva",
    "first_name": "Marco",
    "last_name": "Silva",
    "gender": "Male",
    "date_of_birth": "1988-06-22",
    "date_of_joining": "2022-03-01",
    "company": "Wind Power LLC",
    "department": "Engineering",
    "expense_approver": "Administrator",
    "status": "Active"
}
emp_id = get_or_create("Employee", [["employee_name", "=", "Marco Silva"]], emp_def)

# 4. Save Baseline State (Anti-gaming: track any existing docs)
print("Saving baseline state...")
baseline = {
    "employee_id": emp_id,
    "existing_expense_claims": [doc["name"] for doc in api_get("Expense Claim", [["employee_name", "like", "%Marco%Silva%"]])],
    "existing_payment_entries": [doc["name"] for doc in api_get("Payment Entry", [["party_name", "like", "%Marco%Silva%"], ["party_type", "=", "Employee"]])]
}

with open("/tmp/expense_claim_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print("Baseline saved.")
PYEOF

# Ensure browser is open to the Expense Claim list
echo "Navigating browser to Expense Claim list..."
ensure_firefox_at "http://localhost:8080/app/expense-claim" || true

# Take initial screenshot for visual evidence
sleep 2
take_screenshot /tmp/expense_claim_reimbursement_initial.png 2>/dev/null || true

echo "=== Setup complete ==="