#!/bin/bash
# Setup script for full_procurement_cycle task
# Creates Eagle Hardware supplier, Upper Bearing Plate item, and a submitted Purchase Order
# for 50 units @ $50 each. Agent must create PR → PI → Payment to close the cycle.

set -e
echo "=== Setting up full_procurement_cycle ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date, timedelta

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# --- Login ---
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
for attempt in range(100):  # up to 25 minutes
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

def api_get(doctype, filters=None, fields=None, limit=1):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

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

def safe_submit(doctype, name):
    """Fetch full doc then submit — avoids TimestampMismatchError."""
    time.sleep(1)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit",
                         json={"doc": doc})
    return r_sub

# --- Ensure Supplier: Eagle Hardware ---
print("Setting up supplier: Eagle Hardware")
get_or_create("Supplier",
              [["supplier_name", "=", "Eagle Hardware"]],
              {"supplier_name": "Eagle Hardware",
               "supplier_type": "Company",
               "supplier_group": "All Supplier Groups"})

# --- Ensure Item: Upper Bearing Plate ---
print("Setting up item: Upper Bearing Plate")
item_exists = api_get("Item", [["item_code", "=", "Upper Bearing Plate"]])
if not item_exists:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Upper Bearing Plate",
        "item_name": "Upper Bearing Plate",
        "item_group": "All Item Groups",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "description": "3/16 in. x 6 in. x 6 in. Low Carbon Steel Plate",
        "standard_buying_price": 50.00
    })
    if r.status_code in (200, 201):
        print(f"  Created Item: Upper Bearing Plate")
    else:
        print(f"  ERROR creating Item: {r.status_code} {r.text[:200]}", file=sys.stderr)
else:
    print(f"  Found existing Item: Upper Bearing Plate")

# --- Ensure Warehouse: Stores - WP ---
wh_list = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
stores_wh = wh_list[0]["name"] if wh_list else "Stores - WP"
print(f"  Using warehouse: {stores_wh}")

# --- Create Purchase Order (submitted) ---
today = str(date.today())
required_by = str(date.today() + timedelta(days=7))

# Check if we already created a PO in this setup (avoid duplicates on re-run)
existing_po = api_get("Purchase Order",
                       [["supplier", "=", "Eagle Hardware"],
                        ["docstatus", "=", 1],
                        ["per_received", "=", 0]],
                       fields=["name", "supplier", "status"], limit=5)

po_name = None
if existing_po:
    po_name = existing_po[0]["name"]
    print(f"  Found existing submitted PO: {po_name}")
else:
    # Create PO in draft first
    po_data = {
        "supplier": "Eagle Hardware",
        "transaction_date": today,
        "schedule_date": required_by,
        "company": "Wind Power LLC",
        "currency": "USD",
        "items": [{
            "item_code": "Upper Bearing Plate",
            "item_name": "Upper Bearing Plate",
            "qty": 50,
            "rate": 50.00,
            "uom": "Nos",
            "warehouse": stores_wh,
            "schedule_date": required_by
        }]
    }
    r = session.post(f"{ERPNEXT_URL}/api/resource/Purchase Order", json=po_data)
    if r.status_code not in (200, 201):
        print(f"ERROR creating PO: {r.status_code} {r.text[:400]}", file=sys.stderr)
        sys.exit(1)
    po_name = r.json()["data"]["name"]
    print(f"  Created PO (draft): {po_name}")

    # Submit PO — fetch full doc first to avoid TimestampMismatchError
    r_sub = safe_submit("Purchase Order", po_name)
    if r_sub.status_code in (200, 201):
        print(f"  Submitted PO: {po_name}")
    else:
        print(f"  ERROR submitting PO: {r_sub.status_code} {r_sub.text[:200]}", file=sys.stderr)

# --- Record baseline ---
baseline = {
    "po_name": po_name,
    "supplier": "Eagle Hardware",
    "item_code": "Upper Bearing Plate",
    "qty": 50,
    "rate": 50.00,
    "total": 2500.00,
    "setup_date": today
}
with open("/tmp/full_procurement_cycle_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Supplier:   Eagle Hardware")
print(f"Item:       Upper Bearing Plate (details in baseline JSON)")
print(f"PO:         submitted successfully")
print(f"Baseline:   /tmp/full_procurement_cycle_baseline.json")
PYEOF

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate browser to the Purchase Order
ensure_firefox_at "http://localhost:8080/app/purchase-order"
sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete: PO is submitted, agent must create PR → PI → Payment ==="
