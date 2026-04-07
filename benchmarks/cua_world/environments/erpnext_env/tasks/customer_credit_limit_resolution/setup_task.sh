#!/bin/bash
# Setup script for customer_credit_limit_resolution task
# Creates Customer with a strict $10,000 credit limit, items, and an unpaid $9,500 invoice.

set -e
echo "=== Setting up customer_credit_limit_resolution ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

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

def api_get(doctype, filters=None, fields=None, limit=1):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

print("Waiting for ERPNext master data (Company, Warehouses)...")
master_ready = False
for attempt in range(100):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        warehouses = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
        if companies and warehouses:
            master_ready = True
            break
    except Exception:
        pass
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available after 25 minutes", file=sys.stderr)
    sys.exit(1)

# Re-login
session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})

def safe_submit(doctype, name):
    time.sleep(1)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    return session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit", json={"doc": doc})

# --- Customer with Credit Limit ---
print("Setting up customer: Global Energy Partners")
existing_cust = api_get("Customer", [["customer_name", "=", "Global Energy Partners"]])
if not existing_cust:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Customer", json={
        "customer_name": "Global Energy Partners",
        "customer_type": "Company",
        "customer_group": "All Customer Groups",
        "territory": "All Territories",
        "credit_limits": [{
            "company": "Wind Power LLC",
            "credit_limit": 10000.0,
            "bypass_credit_limit_check": 0
        }]
    })
    if r.status_code not in (200, 201):
        print(f"ERROR creating Customer: {r.text}", file=sys.stderr)

# --- Items ---
for item in [
    {"item_code": "Grid-Tie Inverter", "item_name": "Grid-Tie Inverter", "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 0},
    {"item_code": "Advanced Wind Turbine", "item_name": "Advanced Wind Turbine", "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 0}
]:
    if not api_get("Item", [["item_code", "=", item["item_code"]]]):
        session.post(f"{ERPNEXT_URL}/api/resource/Item", json=item)

# --- Unpaid Sales Invoice ---
print("Creating $9,500 unpaid invoice...")
existing_si = api_get("Sales Invoice", [["customer", "=", "Global Energy Partners"], ["docstatus", "=", 1]])
si_name = ""

if not existing_si:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Sales Invoice", json={
        "customer": "Global Energy Partners",
        "company": "Wind Power LLC",
        "items": [{
            "item_code": "Grid-Tie Inverter",
            "qty": 1,
            "rate": 9500.0
        }]
    })
    if r.status_code in (200, 201):
        si_name = r.json()["data"]["name"]
        safe_submit("Sales Invoice", si_name)
else:
    si_name = existing_si[0]["name"]

print(f"Original SI Name: {si_name}")

# --- Save baseline ---
baseline = {
    "customer": "Global Energy Partners",
    "original_si_name": si_name,
    "strict_limit": 10000.0
}
with open("/tmp/customer_credit_limit_resolution_baseline.json", "w") as f:
    json.dump(baseline, f)

PYEOF

# Take initial screenshot of the starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="