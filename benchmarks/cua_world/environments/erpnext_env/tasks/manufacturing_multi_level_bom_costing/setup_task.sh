#!/bin/bash
# Setup script for manufacturing_multi_level_bom_costing task
# Creates necessary Item Groups, Raw Materials, and sets initial stock/valuation rates.

set -e
echo "=== Setting up manufacturing_multi_level_bom_costing ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time

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
for ig in ["Sub Assemblies", "Products", "Raw Material"]:
    get_or_create("Item Group", [["item_group_name", "=", ig]], 
                  {"item_group_name": ig, "parent_item_group": "All Item Groups", "is_group": 0})

# --- Setup Raw Materials ---
print("Setting up Raw Materials...")
rms = [
    {"item_code": "Wing Sheet", "rate": 15.00, "desc": "1/32 in. x 24 in. x 47 in. HDPE Opaque Sheet"},
    {"item_code": "Shaft", "rate": 25.00, "desc": "1.25 in. Diameter x 6 ft. Mild Steel Tubing"},
    {"item_code": "Upper Bearing Plate", "rate": 60.00, "desc": "3/16 in. x 6 in. x 6 in. Low Carbon Steel Plate"},
    {"item_code": "Base Plate", "rate": 40.00, "desc": "3/4 in. x 2 ft. x 4 ft. Pine Plywood"}
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

# --- Ensure Warehouse: Stores - WP ---
wh_list = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
stores_wh = wh_list[0]["name"] if wh_list else "Stores - WP"

# --- Create Stock Entry (Material Receipt) to establish Valuation Rates ---
print("Setting up inventory stock and valuation rates...")
se_existing = api_get("Stock Entry", [["purpose", "=", "Material Receipt"], ["docstatus", "=", 1]])

if not se_existing:
    se_items = []
    for rm in rms:
        se_items.append({
            "item_code": rm["item_code"],
            "qty": 100,
            "uom": "Nos",
            "t_warehouse": stores_wh,
            "basic_rate": rm["rate"],
            "valuation_rate": rm["rate"]
        })

    se_doc = {
        "doctype": "Stock Entry",
        "purpose": "Material Receipt",
        "company": "Wind Power LLC",
        "items": se_items
    }
    
    r = session.post(f"{ERPNEXT_URL}/api/resource/Stock Entry", json=se_doc)
    if r.status_code in (200, 201):
        se_name = r.json()["data"]["name"]
        safe_submit("Stock Entry", se_name)
        print(f"  Created and submitted initial Stock Entry: {se_name}")
    else:
        print(f"  ERROR creating Stock Entry: {r.text[:200]}", file=sys.stderr)
else:
    print(f"  Found existing Material Receipt: {se_existing[0]['name']}")

PYEOF

echo "=== Task setup complete ==="