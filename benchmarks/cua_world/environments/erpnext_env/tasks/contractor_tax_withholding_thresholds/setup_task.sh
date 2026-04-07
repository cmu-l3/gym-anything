#!/bin/bash
# Setup script for contractor_tax_withholding_thresholds task
# Creates required accounts and the supplier.
# Records baseline state.

set -e
echo "=== Setting up contractor_tax_withholding_thresholds ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=10):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# --- Wait for master data ---
print("Waiting for ERPNext master data (Company)...")
master_ready = False
for attempt in range(100):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        if companies:
            master_ready = True
            break
    except Exception:
        pass
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available", file=sys.stderr)
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

# --- Setup Accounts ---
print("Setting up accounts...")
# Find parent for expense
exp_parents = api_get("Account", [["is_group", "=", 1], ["root_type", "=", "Expense"], ["company", "=", "Wind Power LLC"]])
exp_parent = exp_parents[0]["name"] if exp_parents else "Expenses - WP"

# Find parent for liability
lia_parents = api_get("Account", [["is_group", "=", 1], ["root_type", "=", "Liability"], ["company", "=", "Wind Power LLC"]])
lia_parent = lia_parents[0]["name"] if lia_parents else "Current Liabilities - WP"

get_or_create("Account",
              [["account_name", "=", "Contractor Fees"], ["company", "=", "Wind Power LLC"]],
              {"account_name": "Contractor Fees",
               "parent_account": exp_parent,
               "is_group": 0,
               "company": "Wind Power LLC"})

get_or_create("Account",
              [["account_name", "=", "TDS Payable"], ["company", "=", "Wind Power LLC"]],
              {"account_name": "TDS Payable",
               "parent_account": lia_parent,
               "is_group": 0,
               "account_type": "Tax",
               "company": "Wind Power LLC"})

# --- Setup Supplier ---
print("Setting up supplier...")
get_or_create("Supplier",
              [["supplier_name", "=", "Build-It Construction"]],
              {"supplier_name": "Build-It Construction",
               "supplier_type": "Company",
               "supplier_group": "All Supplier Groups"})

# --- Record Baseline ---
baseline = {
    "setup_time": time.time(),
    "supplier": "Build-It Construction",
    "expense_account": "Contractor Fees - WP",
    "liability_account": "TDS Payable - WP"
}
with open("/tmp/contractor_tax_baseline.json", "w") as f:
    json.dump(baseline, f)

PYEOF

date +%s > /tmp/task_start_time.txt
echo "=== Setup complete ==="