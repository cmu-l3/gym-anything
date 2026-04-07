#!/bin/bash
# Setup script for sales_order_driven_project_template task
# Creates Customer 'Apex Energy' and Service Item 'Wind Farm Installation Service'.
# Records baseline to prevent gaming.

set -e
echo "=== Setting up sales_order_driven_project_template ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (Unix timestamp)
date +%s > /tmp/task_start_time.txt

echo "Waiting for ERPNext..."
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

def api_get(doctype, filters=None, fields=None, limit=1):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# --- Wait for ERPNext master data (before_tests completion check) ---
print("Waiting for ERPNext master data (Company, Warehouses)...")
master_ready = False
for attempt in range(100):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        warehouses = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
        if companies and warehouses:
            print(f"  Master data ready after {attempt * 15}s")
            master_ready = True
            break
    except Exception:
        pass
    print(f"  Master data not ready yet... ({attempt * 15}s elapsed)", flush=True)
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available after 10 minutes", file=sys.stderr)
    sys.exit(1)

# Re-login after waiting
session.post(f"{ERPNEXT_URL}/api/method/login",
             json={"usr": "Administrator", "pwd": "admin"})

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

# --- Customer ---
print("Setting up customer: Apex Energy")
get_or_create("Customer",
              [["customer_name", "=", "Apex Energy"]],
              {"customer_name": "Apex Energy",
               "customer_type": "Company",
               "customer_group": "Commercial",
               "territory": "All Territories"})

# --- Service Item ---
print("Setting up item: Wind Farm Installation Service")
existing_item = api_get("Item", [["item_code", "=", "Wind Farm Installation Service"]])
if not existing_item:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Wind Farm Installation Service",
        "item_name": "Wind Farm Installation Service",
        "item_group": "Services",
        "stock_uom": "Nos",
        "is_stock_item": 0,
        "include_item_in_manufacturing": 0,
        "description": "Professional installation service for wind turbine arrays.",
        "standard_rate": 50000.00
    })
    if r.status_code in (200, 201):
        print(f"  Created Service Item")
    else:
        print(f"  ERROR creating Service Item: {r.text[:200]}", file=sys.stderr)
else:
    print(f"  Found existing Service Item")

# --- Record Baseline ---
print("Recording baseline state...")
baseline = {
    "existing_project_templates": [t["name"] for t in api_get("Project Template", limit=100)],
    "existing_projects": [p["name"] for p in api_get("Project", limit=100)],
    "existing_sales_orders": [so["name"] for so in api_get("Sales Order", limit=100)]
}

with open("/tmp/sales_order_project_baseline.json", "w") as f:
    json.dump(baseline, f)

print("Baseline recorded.")
PYEOF

echo "=== Task setup complete ==="