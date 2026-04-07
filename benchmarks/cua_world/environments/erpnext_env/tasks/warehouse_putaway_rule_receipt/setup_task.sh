#!/bin/bash
set -e
echo "=== Setting up warehouse_putaway_rule_receipt ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date, timedelta

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
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

# Wait for master data
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

session.post(f"{ERPNEXT_URL}/api/method/login",
             json={"usr": "Administrator", "pwd": "admin"})

def api_get(doctype, filters=None, fields=None, limit=50):
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
    time.sleep(1)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit",
                         json={"doc": doc})
    return r_sub

# Setup Supplier
print("Setting up supplier: Eagle Hardware")
get_or_create("Supplier",
              [["supplier_name", "=", "Eagle Hardware"]],
              {"supplier_name": "Eagle Hardware",
               "supplier_type": "Company",
               "supplier_group": "All Supplier Groups"})

# Setup Items
for item_name in ["Rotor Blade", "Gearbox"]:
    print(f"Setting up item: {item_name}")
    existing = api_get("Item", [["item_code", "=", item_name]])
    if not existing:
        session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
            "item_code": item_name,
            "item_name": item_name,
            "item_group": "All Item Groups",
            "stock_uom": "Nos",
            "is_stock_item": 1,
            "has_batch_no": 0,
            "has_serial_no": 0
        })

# Check parent warehouse
stores_wh_list = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
parent_wh = stores_wh_list[0]["name"] if stores_wh_list else "Stores - WP"

# Create child warehouses
for wh_name in ["Blade Rack 1", "Blade Rack 2", "Heavy Parts"]:
    full_name = f"{wh_name} - WP"
    existing = api_get("Warehouse", [["name", "=", full_name]])
    if not existing:
        session.post(f"{ERPNEXT_URL}/api/resource/Warehouse", json={
            "warehouse_name": wh_name,
            "parent_warehouse": parent_wh,
            "company": "Wind Power LLC",
            "is_group": 0
        })
        print(f"Created Warehouse: {full_name}")

# Create Purchase Order
today = str(date.today())
req_by = str(date.today() + timedelta(days=5))

existing_po = api_get("Purchase Order",
                       [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]])
if existing_po:
    po_name = existing_po[-1]["name"]
    print(f"Using existing PO: {po_name}")
else:
    r_po = session.post(f"{ERPNEXT_URL}/api/resource/Purchase Order", json={
        "supplier": "Eagle Hardware",
        "company": "Wind Power LLC",
        "transaction_date": today,
        "schedule_date": req_by,
        "items": [
            {
                "item_code": "Rotor Blade",
                "qty": 60,
                "rate": 1000.00,
                "schedule_date": req_by
            },
            {
                "item_code": "Gearbox",
                "qty": 25,
                "rate": 5000.00,
                "schedule_date": req_by
            }
        ]
    })
    
    if r_po.status_code in (200, 201):
        po_name = r_po.json()["data"]["name"]
        print(f"Created PO: {po_name}")
        r_sub = safe_submit("Purchase Order", po_name)
        if r_sub.status_code == 200:
            print(f"Submitted PO: {po_name}")
        else:
            print(f"Failed to submit PO: {r_sub.text}", file=sys.stderr)
    else:
        print(f"Failed to create PO: {r_po.text}", file=sys.stderr)
        po_name = ""

# Save baseline
baseline = {
    "po_name": po_name,
    "task_start_time": time.time()
}
with open("/tmp/warehouse_putaway_rule_receipt_baseline.json", "w") as f:
    json.dump(baseline, f)

PYEOF

date +%s > /tmp/task_start_time.txt
echo "=== Task setup complete ==="