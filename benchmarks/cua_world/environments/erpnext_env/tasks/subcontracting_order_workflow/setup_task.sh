#!/bin/bash
# Setup script for subcontracting_order_workflow task
# Creates Items, BOM, Supplier, and Pre-stocks raw materials.

set -e
echo "=== Setting up subcontracting_order_workflow ==="

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

def api_get(doctype, filters=None, fields=None, limit=1):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# Wait for master data
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
    print("ERROR: Master data not available", file=sys.stderr)
    sys.exit(1)

# Re-login
session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})

def get_or_create(doctype, filters, values):
    existing = api_get(doctype, filters)
    if existing:
        return existing[0]["name"]
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        return r.json().get("data", {}).get("name")
    print(f"ERROR creating {doctype}: {r.text[:200]}", file=sys.stderr)
    return None

def safe_submit(doctype, name):
    time.sleep(1)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit", json={"doc": doc})
    return r_sub

# Setup Supplier and Warehouse
get_or_create("Supplier", [["supplier_name", "=", "Eagle Hardware"]], {
    "supplier_name": "Eagle Hardware", "supplier_type": "Company", "supplier_group": "All Supplier Groups"
})

get_or_create("Warehouse", [["warehouse_name", "=", "Supplier - Eagle Hardware"]], {
    "warehouse_name": "Supplier - Eagle Hardware", "company": "Wind Power LLC", "parent_warehouse": "All Warehouses - WP", "is_group": 0
})

# Setup Items
items = [
    {"item_code": "Base Plate", "item_name": "Base Plate", "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1, "standard_rate": 40.0},
    {"item_code": "Wing Sheet", "item_name": "Wing Sheet", "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1, "standard_rate": 30.0},
    {"item_code": "Welded Turbine Frame", "item_name": "Welded Turbine Frame", "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1, "is_sub_contracted_item": 1, "default_warehouse": "Stores - WP"},
    {"item_code": "Subcontracting Service - Welding", "item_name": "Subcontracting Service - Welding", "item_group": "Services", "stock_uom": "Nos", "is_stock_item": 0}
]

for item in items:
    get_or_create("Item", [["item_code", "=", item["item_code"]]], item)

# Setup BOM
bom_exists = api_get("BOM", [["item", "=", "Welded Turbine Frame"], ["docstatus", "=", 1]])
if not bom_exists:
    r = session.post(f"{ERPNEXT_URL}/api/resource/BOM", json={
        "item": "Welded Turbine Frame", "company": "Wind Power LLC", "quantity": 1, "is_active": 1, "is_default": 1, "with_operations": 0,
        "items": [
            {"item_code": "Base Plate", "qty": 1, "rate": 40, "uom": "Nos", "stock_uom": "Nos"},
            {"item_code": "Wing Sheet", "qty": 2, "rate": 30, "uom": "Nos", "stock_uom": "Nos"}
        ]
    })
    if r.status_code in (200, 201):
        bom_name = r.json().get("data", {}).get("name")
        safe_submit("BOM", bom_name)

# Stock Raw Materials
stores_wh = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])[0]["name"]
for raw_item, qty in [("Base Plate", 50), ("Wing Sheet", 50)]:
    stock = api_get("Bin", [["item_code", "=", raw_item], ["warehouse", "=", stores_wh]], ["actual_qty"])
    if not stock or float(stock[0].get("actual_qty", 0)) < qty:
        r = session.post(f"{ERPNEXT_URL}/api/resource/Stock Entry", json={
            "stock_entry_type": "Material Receipt", "company": "Wind Power LLC",
            "items": [{"item_code": raw_item, "qty": qty, "t_warehouse": stores_wh, "conversion_factor": 1}]
        })
        if r.status_code in (200, 201):
            se_name = r.json().get("data", {}).get("name")
            safe_submit("Stock Entry", se_name)

# Record Baseline
def get_stock(item_code, wh):
    b = api_get("Bin", [["item_code", "=", item_code], ["warehouse", "=", wh]], ["actual_qty"])
    return float(b[0]["actual_qty"]) if b else 0.0

supplier_wh = api_get("Warehouse", [["warehouse_name", "=", "Supplier - Eagle Hardware"]])[0]["name"]

baseline = {
    "stores_wh": stores_wh,
    "supplier_wh": supplier_wh,
    "stores_base_plate_before": get_stock("Base Plate", stores_wh),
    "stores_wing_sheet_before": get_stock("Wing Sheet", stores_wh),
    "stores_frame_before": get_stock("Welded Turbine Frame", stores_wh),
    "supplier_base_plate_before": get_stock("Base Plate", supplier_wh),
    "supplier_wing_sheet_before": get_stock("Wing Sheet", supplier_wh)
}

with open("/tmp/subcontracting_baseline.json", "w") as f:
    json.dump(baseline, f)

PYEOF

echo "Navigating browser to Subcontracting Order list..."
ensure_firefox_at "http://localhost:8080/app/subcontracting-order"

echo "$(date +%s)" > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup complete ==="