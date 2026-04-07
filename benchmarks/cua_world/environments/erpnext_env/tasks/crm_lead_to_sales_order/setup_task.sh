#!/bin/bash
# Setup script for crm_lead_to_sales_order task
# Prepares the ERPNext environment: ensures the item exists, ensures the Lead Source exists,
# and actively wipes any existing documents related to the target company to prevent gaming.

set -e
echo "=== Setting up crm_lead_to_sales_order ==="

# Record task start time (epoch) for anti-gaming checks
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=100):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params)
    if resp.status_code == 200:
        return resp.json().get("data", [])
    return []

# --- Wait for ERPNext master data (before_tests completion check) ---
print("Waiting for ERPNext master data...")
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

# Re-login after wait
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

def delete_docs(doctype, filters):
    docs = api_get(doctype, filters, ["name"])
    for d in docs:
        name = d["name"]
        # Cancel first if submitted
        session.post(f"{ERPNEXT_URL}/api/method/frappe.client.cancel", json={"doctype": doctype, "name": name})
        # Delete
        r = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.delete", json={"doctype": doctype, "name": name})
        print(f"  Deleted existing {doctype} {name}: {r.status_code}")

# --- Clean up any existing Greenfield documents to ensure clean state ---
print("Cleaning up old Greenfield Renewable Solutions data...")
delete_docs("Sales Order", [["customer_name", "like", "%Greenfield%"]])
delete_docs("Quotation", [["party_name", "like", "%Greenfield%"]])
delete_docs("Opportunity", [["party_name", "like", "%Greenfield%"]])
delete_docs("Lead", [["company_name", "like", "%Greenfield%"]])
delete_docs("Customer", [["customer_name", "like", "%Greenfield%"]])

# --- Ensure Lead Source exists ---
get_or_create("Lead Source", [["source_name", "=", "Trade Show"]], {"source_name": "Trade Show"})

# --- Ensure Item exists ---
item_exists = api_get("Item", [["item_code", "=", "Wind Turbine"]])
if not item_exists:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Wind Turbine",
        "item_name": "Wind Turbine",
        "item_group": "Products",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "standard_rate": 21.00
    })
    if r.status_code in (200, 201):
        print(f"  Created Item: Wind Turbine")
else:
    print(f"  Found existing Item: Wind Turbine")

# --- Ensure Selling Price ---
price_exists = api_get("Item Price", [["item_code", "=", "Wind Turbine"], ["selling", "=", 1]])
if not price_exists:
    session.post(f"{ERPNEXT_URL}/api/resource/Item Price", json={
        "item_code": "Wind Turbine",
        "price_list": "Standard Selling",
        "price_list_rate": 21.00,
        "selling": 1
    })
PYEOF

# Ensure Firefox is open and logged in, navigating to Lead list
echo "Navigating to Lead list..."
ensure_firefox_at "http://localhost:8080/app/lead"

# Small delay to ensure page rendering
sleep 5
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="