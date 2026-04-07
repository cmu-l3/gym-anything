#!/bin/bash
# Setup script for drop_shipping_workflow_execution task
# Creates Customer (Apex Corp), Supplier (Global Solar Supply), and Item (Industrial Solar Inverter)
# with 0 initial inventory. Agent must complete Drop Ship cycle (SO -> PO -> DN).

set -e
echo "=== Setting up drop_shipping_workflow_execution ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

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
    existing = api_get(doctype, filters, limit=10)
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

# --- Setup Master Data ---
print("Setting up customer: Apex Corp")
get_or_create("Customer",
              [["customer_name", "=", "Apex Corp"]],
              {"customer_name": "Apex Corp",
               "customer_type": "Company",
               "customer_group": "All Customer Groups",
               "territory": "All Territories"})

print("Setting up supplier: Global Solar Supply")
get_or_create("Supplier",
              [["supplier_name", "=", "Global Solar Supply"]],
              {"supplier_name": "Global Solar Supply",
               "supplier_type": "Company",
               "supplier_group": "All Supplier Groups"})

print("Setting up item: Industrial Solar Inverter")
existing_item = api_get("Item", [["item_code", "=", "Industrial Solar Inverter"]], limit=1)
if not existing_item:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Industrial Solar Inverter",
        "item_name": "Industrial Solar Inverter",
        "item_group": "All Item Groups",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "description": "High efficiency 10kW Industrial Solar Inverter",
        "standard_rate": 1500.00
    })
    if r.status_code in (200, 201):
        print("  Created Item: Industrial Solar Inverter")
    else:
        print(f"  ERROR creating Item: {r.text[:200]}", file=sys.stderr)
else:
    print("  Found existing Item: Industrial Solar Inverter")

# Ensure no residual stock from earlier runs
session.delete(f"{ERPNEXT_URL}/api/resource/Stock Ledger Entry", params={"filters": json.dumps([["item_code", "=", "Industrial Solar Inverter"]])})

# Record Baseline
baseline = {
    "setup_time": time.time(),
    "item_code": "Industrial Solar Inverter",
    "customer": "Apex Corp",
    "supplier": "Global Solar Supply",
    "existing_so": [d["name"] for d in api_get("Sales Order", [["customer", "=", "Apex Corp"]], limit=50)],
    "existing_po": [d["name"] for d in api_get("Purchase Order", [["supplier", "=", "Global Solar Supply"]], limit=50)],
    "existing_dn": [d["name"] for d in api_get("Delivery Note", [["customer", "=", "Apex Corp"]], limit=50)]
}

with open("/tmp/drop_shipping_workflow_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print("Baseline recorded.")
PYEOF

echo "=== Task setup complete ==="