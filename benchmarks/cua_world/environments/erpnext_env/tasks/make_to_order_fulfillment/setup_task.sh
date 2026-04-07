#!/bin/bash
# Setup script for make_to_order_fulfillment task
# Creates raw materials with stock, configures manufacturing settings,
# ensures customer exists. Agent must create item, BOM, SO, WO, stock entries,
# DN, SINV, and Payment to complete the make-to-order cycle.

set -e
echo "=== Setting up make_to_order_fulfillment ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Delete stale outputs BEFORE recording timestamp
rm -f /tmp/make_to_order_fulfillment_result.json 2>/dev/null || true
rm -f /tmp/make_to_order_fulfillment_baseline.json 2>/dev/null || true
rm -f /tmp/make_to_order_fulfillment_final.png 2>/dev/null || true

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
    """Fetch full doc then submit — avoids TimestampMismatchError."""
    time.sleep(1)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit",
                         json={"doc": doc})
    return r_sub

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

# --- Ensure Item Groups ---
print("Setting up Item Groups...")
for ig in ["Products", "Raw Material"]:
    get_or_create("Item Group", [["item_group_name", "=", ig]],
                  {"item_group_name": ig, "parent_item_group": "All Item Groups", "is_group": 0})

# --- Setup Raw Materials ---
print("Setting up Raw Materials...")
rms = [
    {"item_code": "Shaft",               "rate": 30.00, "desc": "1.25 in. Diameter x 6 ft. Mild Steel Tubing"},
    {"item_code": "Wing Sheet",           "rate": 22.00, "desc": "1/32 in. x 24 in. x 47 in. HDPE Opaque Sheet"},
    {"item_code": "Upper Bearing Plate",  "rate": 50.00, "desc": "3/16 in. x 6 in. x 6 in. Low Carbon Steel Plate"},
    {"item_code": "Base Plate",           "rate": 20.00, "desc": "3/4 in. x 2 ft. x 4 ft. Pine Plywood"}
]

for rm in rms:
    item_def = {
        "item_code": rm["item_code"],
        "item_name": rm["item_code"],
        "item_group": "Raw Material",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "description": rm["desc"],
        "standard_rate": rm["rate"],
        "valuation_rate": rm["rate"]
    }
    get_or_create("Item", [["item_code", "=", rm["item_code"]]], item_def)

# --- Ensure Warehouses ---
wh_list = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
stores_wh = wh_list[0]["name"] if wh_list else "Stores - WP"
print(f"  Using Stores warehouse: {stores_wh}")

wip_list = api_get("Warehouse", [["warehouse_name", "=", "Work In Progress"]])
wip_wh = wip_list[0]["name"] if wip_list else "Work In Progress - WP"
print(f"  Using WIP warehouse: {wip_wh}")

fg_list = api_get("Warehouse", [["warehouse_name", "=", "Finished Goods"]])
fg_wh = fg_list[0]["name"] if fg_list else "Finished Goods - WP"
print(f"  Using FG warehouse: {fg_wh}")

# --- Create WIP and FG warehouses if they don't exist ---
for wh_name, wh_full in [("Work In Progress", wip_wh), ("Finished Goods", fg_wh)]:
    existing = api_get("Warehouse", [["name", "=", wh_full]])
    if not existing:
        print(f"  Creating warehouse: {wh_full}")
        get_or_create("Warehouse", [["warehouse_name", "=", wh_name]],
                      {"warehouse_name": wh_name, "company": "Wind Power LLC",
                       "parent_warehouse": "All Warehouses - WP"})

# --- Stock raw materials via Material Receipt ---
print("Stocking raw materials in Stores warehouse...")
# Check if we already have stock (avoid duplicates on re-run)
needs_stock = False
for rm in rms:
    try:
        r = session.get(f"{ERPNEXT_URL}/api/method/erpnext.stock.utils.get_stock_balance",
                        params={"item_code": rm["item_code"], "warehouse": stores_wh})
        bal = float(r.json().get("message", 0) or 0)
        if bal < 50:
            needs_stock = True
            break
    except Exception:
        needs_stock = True
        break

if needs_stock:
    # Quantities: need 10 Shafts, 30 Wing Sheets, 10 UBP, 10 BP for 10 turbines
    # Stock generous amounts with buffer
    se_items = [
        {"item_code": "Shaft",              "qty": 50,  "uom": "Nos", "t_warehouse": stores_wh, "basic_rate": 30.00},
        {"item_code": "Wing Sheet",          "qty": 150, "uom": "Nos", "t_warehouse": stores_wh, "basic_rate": 22.00},
        {"item_code": "Upper Bearing Plate", "qty": 50,  "uom": "Nos", "t_warehouse": stores_wh, "basic_rate": 50.00},
        {"item_code": "Base Plate",          "qty": 50,  "uom": "Nos", "t_warehouse": stores_wh, "basic_rate": 20.00}
    ]
    se_doc = {
        "doctype": "Stock Entry",
        "stock_entry_type": "Material Receipt",
        "purpose": "Material Receipt",
        "company": "Wind Power LLC",
        "items": se_items
    }
    r = session.post(f"{ERPNEXT_URL}/api/resource/Stock Entry", json=se_doc)
    if r.status_code in (200, 201):
        se_name = r.json()["data"]["name"]
        r_sub = safe_submit("Stock Entry", se_name)
        if r_sub.status_code in (200, 201):
            print(f"  Created and submitted Stock Entry (Material Receipt): {se_name}")
        else:
            print(f"  ERROR submitting Stock Entry: {r_sub.status_code} {r_sub.text[:200]}", file=sys.stderr)
    else:
        print(f"  ERROR creating Stock Entry: {r.status_code} {r.text[:200]}", file=sys.stderr)
else:
    print("  Raw materials already stocked (skipping Material Receipt)")

# --- Configure Manufacturing Settings ---
print("Configuring Manufacturing Settings...")
try:
    r = session.put(f"{ERPNEXT_URL}/api/resource/Manufacturing Settings/Manufacturing Settings",
                    json={
                        "default_wip_warehouse": wip_wh,
                        "default_fg_warehouse": fg_wh
                    })
    if r.status_code in (200, 201):
        print(f"  Manufacturing Settings updated: WIP={wip_wh}, FG={fg_wh}")
    else:
        # Try alternative method
        session.post(f"{ERPNEXT_URL}/api/method/frappe.client.set_value",
                     json={"doctype": "Manufacturing Settings",
                           "name": "Manufacturing Settings",
                           "fieldname": "default_wip_warehouse",
                           "value": wip_wh})
        session.post(f"{ERPNEXT_URL}/api/method/frappe.client.set_value",
                     json={"doctype": "Manufacturing Settings",
                           "name": "Manufacturing Settings",
                           "fieldname": "default_fg_warehouse",
                           "value": fg_wh})
        print(f"  Manufacturing Settings updated via set_value fallback")
except Exception as e:
    print(f"  WARNING: Could not update Manufacturing Settings: {e}", file=sys.stderr)

# --- Ensure Customer: Buttrey Food & Drug ---
print("Setting up customer: Buttrey Food & Drug")
get_or_create("Customer",
              [["customer_name", "=", "Buttrey Food & Drug"]],
              {"customer_name": "Buttrey Food & Drug",
               "customer_group": "All Customer Groups",
               "territory": "United States"})

# --- Record baseline snapshot ---
print("Recording baseline snapshot...")
baseline = {
    "setup_date": str(date.today()),
    "stores_warehouse": stores_wh,
    "wip_warehouse": wip_wh,
    "fg_warehouse": fg_wh,
    "existing_items": [d["name"] for d in api_get("Item", limit=200)],
    "existing_boms": [d["name"] for d in api_get("BOM", limit=200)],
    "existing_sales_orders": [d["name"] for d in api_get("Sales Order", limit=200)],
    "existing_work_orders": [d["name"] for d in api_get("Work Order", limit=200)],
    "existing_stock_entries": [d["name"] for d in api_get("Stock Entry", limit=200)],
    "existing_delivery_notes": [d["name"] for d in api_get("Delivery Note", limit=200)],
    "existing_sales_invoices": [d["name"] for d in api_get("Sales Invoice", limit=200)],
    "existing_payment_entries": [d["name"] for d in api_get("Payment Entry", limit=200)]
}
# Record stock levels for raw materials
for rm in rms:
    try:
        r = session.get(f"{ERPNEXT_URL}/api/method/erpnext.stock.utils.get_stock_balance",
                        params={"item_code": rm["item_code"], "warehouse": stores_wh})
        baseline[f"stock_{rm['item_code']}"] = float(r.json().get("message", 0) or 0)
    except Exception:
        baseline[f"stock_{rm['item_code']}"] = 0

with open("/tmp/make_to_order_fulfillment_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Customer:     Buttrey Food & Drug")
print(f"Raw Materials: Shaft, Wing Sheet, Upper Bearing Plate, Base Plate (stocked)")
print(f"Warehouses:   Stores={stores_wh}, WIP={wip_wh}, FG={fg_wh}")
print(f"Baseline:     /tmp/make_to_order_fulfillment_baseline.json")
PYEOF

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate browser to ERPNext home
ensure_firefox_at "http://localhost:8080/app/home"
sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete: agent must create Item, BOM, SO, WO, Stock Entries, DN, SINV, Payment ==="
