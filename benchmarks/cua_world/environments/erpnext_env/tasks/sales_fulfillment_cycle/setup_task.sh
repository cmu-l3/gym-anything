#!/bin/bash
# Setup script for sales_fulfillment_cycle task
# Creates customer, items (with inventory), and a submitted Sales Order.
# Agent must create Delivery Note → Sales Invoice → Payment Entry.

set -e
echo "=== Setting up sales_fulfillment_cycle ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date, timedelta

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

def api_get(doctype, filters=None, fields=None, limit=10):
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

# --- Customer ---
print("Setting up customer: Consumers and Consumers Express")
get_or_create("Customer",
              [["customer_name", "=", "Consumers and Consumers Express"]],
              {"customer_name": "Consumers and Consumers Express",
               "customer_type": "Company",
               "customer_group": "All Customer Groups",
               "territory": "All Territories"})

# --- Items ---
for item_def in [
    {"item_code": "Wind Turbine", "item_name": "Wind Turbine",
     "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1,
     "description": "Small Wind Turbine for Home Use", "standard_rate": 21.00},
    {"item_code": "Wind Mill A Series", "item_name": "Wind Mill A Series",
     "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1,
     "description": "Wind Mill A Series for Home Use 9ft", "standard_rate": 28.00}
]:
    print(f"Setting up item: {item_def['item_code']}")
    existing = api_get("Item", [["item_code", "=", item_def["item_code"]]])
    if not existing:
        r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json=item_def)
        if r.status_code in (200, 201):
            print(f"  Created Item: {item_def['item_code']}")
        else:
            print(f"  ERROR creating Item: {r.status_code} {r.text[:200]}", file=sys.stderr)
    else:
        print(f"  Found existing Item: {item_def['item_code']}")

# --- Determine warehouses ---
wh_rows = api_get("Warehouse", fields=["name", "warehouse_name"])
stores_wh = next((w["name"] for w in wh_rows if "Stores" in w["name"]), "Stores - WP")
fg_wh = next((w["name"] for w in wh_rows if "Finished Goods" in w["name"]), "Finished Goods - WP")
print(f"  Stores warehouse: {stores_wh}")
print(f"  FG warehouse: {fg_wh}")

# --- Pre-stock Wind Turbine and Wind Mill A Series ---
# Use a Material Receipt stock entry so the Delivery Note can ship them
def get_item_stock(item_code, warehouse):
    resp = session.get(f"{ERPNEXT_URL}/api/method/frappe.client.get_value",
                       params={"doctype": "Bin",
                               "filters": json.dumps([["item_code", "=", item_code],
                                                       ["warehouse", "=", warehouse]]),
                               "fieldname": "actual_qty"})
    val = resp.json().get("message", {})
    if isinstance(val, dict):
        return float(val.get("actual_qty", 0))
    return 0.0

for item_code, needed_qty in [("Wind Turbine", 25), ("Wind Mill A Series", 15)]:
    current_stock = get_item_stock(item_code, stores_wh)
    print(f"  Current stock {item_code} in {stores_wh}: {current_stock}")
    if current_stock < needed_qty:
        receipt_qty = needed_qty - current_stock
        print(f"  Adding {receipt_qty} units of {item_code} to {stores_wh}...")
        se_data = {
            "stock_entry_type": "Material Receipt",
            "purpose": "Material Receipt",
            "company": "Wind Power LLC",
            "items": [{
                "item_code": item_code,
                "qty": receipt_qty,
                "t_warehouse": stores_wh,
                "basic_rate": 15.00  # internal cost
            }]
        }
        r = session.post(f"{ERPNEXT_URL}/api/resource/Stock Entry", json=se_data)
        if r.status_code in (200, 201):
            se_name = r.json()["data"]["name"]
            print(f"  Created Stock Entry: {se_name}")
            r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit",
                                  json={"doc": {"doctype": "Stock Entry", "name": se_name}})
            if r_sub.status_code in (200, 201):
                print(f"  Submitted Stock Entry: {se_name}")
            else:
                print(f"  WARNING: Could not submit SE: {r_sub.text[:200]}", file=sys.stderr)
        else:
            print(f"  ERROR creating Stock Entry: {r.text[:200]}", file=sys.stderr)

# --- Create and submit Sales Order ---
today = str(date.today())
delivery_date = str(date.today() + timedelta(days=7))

existing_so = api_get("Sales Order",
                        [["customer", "=", "Consumers and Consumers Express"],
                         ["docstatus", "=", 1],
                         ["per_delivered", "=", 0]],
                        fields=["name"], limit=5)
so_name = None
if existing_so:
    so_name = existing_so[0]["name"]
    print(f"  Found existing submitted SO: {so_name}")
else:
    so_data = {
        "customer": "Consumers and Consumers Express",
        "transaction_date": today,
        "delivery_date": delivery_date,
        "company": "Wind Power LLC",
        "currency": "USD",
        "items": [
            {"item_code": "Wind Turbine", "item_name": "Wind Turbine",
             "qty": 20, "rate": 21.00, "uom": "Nos",
             "delivery_date": delivery_date, "warehouse": stores_wh},
            {"item_code": "Wind Mill A Series", "item_name": "Wind Mill A Series",
             "qty": 10, "rate": 28.00, "uom": "Nos",
             "delivery_date": delivery_date, "warehouse": stores_wh}
        ]
    }
    r = session.post(f"{ERPNEXT_URL}/api/resource/Sales Order", json=so_data)
    if r.status_code not in (200, 201):
        print(f"ERROR creating SO: {r.status_code} {r.text[:400]}", file=sys.stderr)
        sys.exit(1)
    so_name = r.json()["data"]["name"]
    print(f"  Created SO (draft): {so_name}")

    r_sub = safe_submit("Sales Order", so_name)
    if r_sub.status_code in (200, 201):
        print(f"  Submitted SO: {so_name}")
    else:
        print(f"  ERROR submitting SO: {r_sub.text[:200]}", file=sys.stderr)

# --- Record baseline ---
baseline = {
    "so_name": so_name,
    "customer": "Consumers and Consumers Express",
    "items": [
        {"item_code": "Wind Turbine", "qty": 20, "rate": 21.00},
        {"item_code": "Wind Mill A Series", "qty": 10, "rate": 28.00}
    ],
    "total": 700.00,
    "setup_date": today
}
with open("/tmp/sales_fulfillment_cycle_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Customer: Consumers and Consumers Express")
print(f"SO:       submitted, inventory stocked")
print(f"Status:   awaiting Delivery Note → Sales Invoice → Payment")
PYEOF

date +%s > /tmp/task_start_timestamp

ensure_firefox_at "http://localhost:8080/app/sales-order"
sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete: SO is submitted, agent must create DN → SI → Payment ==="
