#!/bin/bash
# Setup script for regional_tax_configuration_and_sales_order task
# Creates Maple Leaf Wind customer, ensures Wind Turbine item exists with $5000 rate,
# and verifies 'Duties and Taxes - WP' parent account exists.

set -e
echo "=== Setting up regional_tax_configuration_and_sales_order ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

# Run Python setup script to configure initial ERPNext state
python3 << 'PYEOF'
import requests, json, sys, time, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# --- Login ---
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

# --- Wait for ERPNext master data ---
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
    print("ERROR: ERPNext master data not available after 10 minutes", file=sys.stderr)
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

# --- Create Customer ---
print("Setting up customer: Maple Leaf Wind")
get_or_create("Customer",
              [["customer_name", "=", "Maple Leaf Wind"]],
              {"customer_name": "Maple Leaf Wind",
               "customer_type": "Company",
               "customer_group": "Commercial",
               "territory": "All Territories"})

# --- Ensure Item ---
print("Setting up item: Wind Turbine")
existing_item = api_get("Item", [["item_code", "=", "Wind Turbine"]])
if not existing_item:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Wind Turbine",
        "item_name": "Wind Turbine",
        "item_group": "Products",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "standard_rate": 5000.00
    })
    print(f"  Item creation status: {r.status_code}")
else:
    # Ensure rate is 5000 for standard pricing
    session.put(f"{ERPNEXT_URL}/api/resource/Item/Wind Turbine", json={"standard_rate": 5000.00})
    print(f"  Found existing Item: Wind Turbine (rate set to $5000)")

# --- Ensure Parent Tax Account Exists ---
print("Verifying 'Duties and Taxes' parent account exists...")
duties_acc = api_get("Account", [["account_name", "like", "Duties and Taxes%"], ["company", "=", "Wind Power LLC"]])
if not duties_acc:
    print("  WARNING: Duties and Taxes account not found. It should be created by default.")

# --- Save Baseline State ---
baseline = {
    "task_start_time": time.time(),
    "company": "Wind Power LLC",
    "customer": "Maple Leaf Wind",
    "timestamp_iso": str(time.strftime("%Y-%m-%dT%H:%M:%S"))
}
with open("/tmp/regional_tax_baseline.json", "w") as f:
    json.dump(baseline, f)

print("Setup complete. Baseline saved.")
PYEOF

# Take initial screenshot showing clean state
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/regional_tax_initial.png 2>/dev/null || true

echo "=== Setup complete ==="