#!/bin/bash
# Setup script for deferred_revenue_accounting task
# Creates a 2026 Fiscal Year, 'Green Energy Corp' customer, and ensures
# 'Deferred Revenue - WP' account exists under Current Liabilities.

set -e
echo "=== Setting up deferred_revenue_accounting ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

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

# Wait for master data to settle down
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

# Re-login after wait
session.post(f"{ERPNEXT_URL}/api/method/login",
             json={"usr": "Administrator", "pwd": "admin"})

def get_or_create(doctype, filters, values):
    existing = api_get(doctype, filters)
    if existing:
        return existing[0]["name"]
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        print(f"Created {doctype}: {r.json().get('data', {}).get('name')}")
        return r.json().get("data", {}).get("name", "unknown")
    print(f"ERROR creating {doctype}: {r.text}", file=sys.stderr)
    return None

# Fiscal Year 2026
get_or_create("Fiscal Year", [["year", "=", "2026"]], {
    "year": "2026",
    "year_start_date": "2026-01-01",
    "year_end_date": "2026-12-31",
    "companies": [{"company": "Wind Power LLC"}]
})

# Customer
get_or_create("Customer", [["customer_name", "=", "Green Energy Corp"]], {
    "customer_name": "Green Energy Corp",
    "customer_type": "Company",
    "customer_group": "All Customer Groups",
    "territory": "All Territories"
})

# Deferred Revenue Account
parent_accs = api_get("Account", [["account_name", "like", "Current Liabilities%"], ["company", "=", "Wind Power LLC"]], fields=["name"])
parent_acc = parent_accs[0]["name"] if parent_accs else "Current Liabilities - WP"

get_or_create("Account", [["account_name", "=", "Deferred Revenue"], ["company", "=", "Wind Power LLC"]], {
    "account_name": "Deferred Revenue",
    "parent_account": parent_acc,
    "company": "Wind Power LLC",
    "is_group": 0,
    "account_type": "Current Liability"
})

print("Setup Complete")
PYEOF

echo "=== Task setup complete ==="